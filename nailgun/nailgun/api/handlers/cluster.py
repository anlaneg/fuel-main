# -*- coding: utf-8 -*-

import json
import uuid
import itertools

import web
import netaddr

import nailgun.rpc as rpc
from nailgun.settings import settings
from nailgun.logger import logger
from nailgun.api.models import Cluster
from nailgun.api.models import Node
from nailgun.api.models import Network
from nailgun.api.models import Release
from nailgun.api.models import Attributes
from nailgun.api.models import IPAddr
from nailgun.api.models import Vlan
from nailgun.api.models import Task

from nailgun.api.handlers.base import JSONHandler
from nailgun.api.handlers.node import NodeHandler
from nailgun.api.handlers.tasks import TaskHandler
from nailgun.network import manager as netmanager
from nailgun.taskmanager.manager import DeploymentTaskManager
from nailgun.taskmanager.errors import FailedProvisioning
from nailgun.taskmanager.errors import DeploymentAlreadyStarted
from nailgun.taskmanager.errors import WrongNodeStatus


class ClusterHandler(JSONHandler):
    fields = (
        "id",
        "name",
        "type",
        "mode",
        "redundancy",
        ("nodes", "*"),
        ("release", "*")
    )
    model = Cluster

    @classmethod
    def render(cls, instance, fields=None):
        json_data = JSONHandler.render(instance, fields=cls.fields)
        json_data["tasks"] = map(
            TaskHandler.render,
            instance.tasks
        )
        return json_data

    def GET(self, cluster_id):
        web.header('Content-Type', 'application/json')
        q = web.ctx.orm.query(Cluster)
        cluster = q.filter(Cluster.id == cluster_id).first()
        if not cluster:
            return web.notfound()
        return json.dumps(
            self.render(cluster),
            indent=4
        )

    def PUT(self, cluster_id):
        web.header('Content-Type', 'application/json')
        q = web.ctx.orm.query(Cluster).filter(Cluster.id == cluster_id)
        cluster = q.first()
        if not cluster:
            return web.notfound()
        # additional validation needed?
        data = Cluster.validate_json(web.data())
        # /additional validation needed?
        for key, value in data.iteritems():
            if key == "nodes":
                map(cluster.nodes.remove, cluster.nodes)
                nodes = web.ctx.orm.query(Node).filter(
                    Node.id.in_(value)
                )
                map(cluster.nodes.append, nodes)
            else:
                setattr(cluster, key, value)
        web.ctx.orm.add(cluster)
        web.ctx.orm.commit()
        return json.dumps(
            self.render(cluster),
            indent=4
        )

    def DELETE(self, cluster_id):
        cluster = web.ctx.orm.query(Cluster).filter(
            Cluster.id == cluster_id
        ).first()
        if not cluster:
            return web.notfound()
        for node in cluster.nodes:
            node.role = None
        web.ctx.orm.delete(cluster)
        web.ctx.orm.commit()
        raise web.webapi.HTTPError(
            status="204 No Content",
            data=""
        )


class ClusterCollectionHandler(JSONHandler):
    def GET(self):
        web.header('Content-Type', 'application/json')
        return json.dumps(map(
            ClusterHandler.render,
            web.ctx.orm.query(Cluster).all()
        ), indent=4)

    def POST(self):
        web.header('Content-Type', 'application/json')
        data = Cluster.validate(web.data())

        cluster = Cluster()
        cluster.release = web.ctx.orm.query(Release).get(data["release"])

        # TODO: discover how to add multiple objects
        if 'nodes' in data and data['nodes']:
            nodes = web.ctx.orm.query(Node).filter(
                Node.id.in_(data['nodes'])
            )
            map(cluster.nodes.append, nodes)

        # TODO: use fields
        for field in ('name', 'type', 'mode', 'redundancy'):
            setattr(cluster, field, data.get(field))

        web.ctx.orm.add(cluster)
        web.ctx.orm.commit()
        attributes = Attributes(
            editable=cluster.release.attributes_metadata.get("editable"),
            generated=cluster.release.attributes_metadata.get("generated"),
            cluster=cluster
        )
        web.ctx.orm.add(attributes)
        web.ctx.orm.commit()
        attributes.generate_fields()
        web.ctx.orm.add(attributes)
        web.ctx.orm.commit()

        used_nets = [n.cidr for n in web.ctx.orm.query(Network).all()]
        used_vlans = [v.id for v in web.ctx.orm.query(Vlan).all()]

        for network in cluster.release.networks_metadata:
            new_vlan = sorted(list(set(range(int(settings.VLANS_RANGE_START),
                                             int(settings.VLANS_RANGE_END))) -
                                   set(used_vlans)))[0]
            vlan_db = Vlan(id=new_vlan)
            web.ctx.orm.add(vlan_db)
            web.ctx.orm.commit()

            pool = settings.NETWORK_POOLS[network['access']]
            nets_free_set = netaddr.IPSet(pool) -\
                netaddr.IPSet(settings.NET_EXCLUDE) -\
                netaddr.IPSet(used_nets)

            free_cidrs = sorted(list(nets_free_set._cidrs))
            new_net = list(free_cidrs[0].subnet(24, count=1))[0]

            nw_db = Network(
                release=cluster.release.id,
                name=network['name'],
                access=network['access'],
                cidr=str(new_net),
                gateway=str(new_net[1]),
                cluster_id=cluster.id,
                vlan_id=vlan_db.id
            )
            web.ctx.orm.add(nw_db)
            web.ctx.orm.commit()

            used_vlans.append(new_vlan)
            used_nets.append(str(new_net))

        raise web.webapi.created(json.dumps(
            ClusterHandler.render(cluster),
            indent=4
        ))


class ClusterChangesHandler(JSONHandler):
    fields = (
        "id",
        "name",
    )

    def PUT(self, cluster_id):
        web.header('Content-Type', 'application/json')
        q = web.ctx.orm.query(Cluster).filter(Cluster.id == cluster_id)
        cluster = q.first()
        if not cluster:
            return web.notfound()

        task_manager = DeploymentTaskManager(cluster=cluster)
        # might be different logic for any error type
        try:
            task = task_manager.start_deployment()
        except DeploymentAlreadyStarted as exc:
            raise web.badrequest(exc.message)
        except FailedProvisioning as exc:
            raise web.badrequest(exc.message)
        except WrongNodeStatus as exc:
            raise web.badrequest(exc.message)

        nodes_to_delete = []
        for node in cluster.nodes:
            if node.pending_deletion:
                nodes_to_delete.append({
                    'id': node.id,
                    'uid': node.id
                })
        if nodes_to_delete:
            msg_delete = {
                'method': 'remove_nodes',
                'respond_to': 'remove_nodes_resp',
                'args': {
                    'task_uuid': task.uuid,
                    'nodes': nodes_to_delete
                }
            }
            rpc.cast('naily', msg_delete)

        netmanager.assign_ips(cluster_id, "management")

        nodes = []
        for n in cluster.nodes:
            if not node.pending_deletion:
                nodes.append({
                    'id': n.id, 'status': n.status, 'uid': n.id,
                    'ip': n.ip, 'mac': n.mac, 'role': n.role,
                    'network_data': netmanager.get_node_networks(n.id)
                })

        message = {
            'method': 'deploy',
            'respond_to': 'deploy_resp',
            'args': {
                'task_uuid': task.uuid,
                'nodes': nodes,
                'attributes': cluster.attributes.merged_attrs()
            }
        }
        rpc.cast('naily', message)

        return json.dumps(
            TaskHandler.render(task),
            indent=4
        )


class ClusterNetworksHandler(JSONHandler):
    fields = (
        "id",
        "name",
    )

    def PUT(self, cluster_id):
        web.header('Content-Type', 'application/json')
        q = web.ctx.orm.query(Cluster).filter(Cluster.id == cluster_id)
        cluster = q.first()
        if not cluster:
            return web.notfound()

        task = Task(
            uuid=str(uuid.uuid4()),
            name="verify_networks",
            cluster=cluster
        )
        web.ctx.orm.add(task)
        web.ctx.orm.commit()

        nets_db = web.ctx.orm.query(Network).filter_by(
            cluster_id=cluster_id).all()
        networks = [{
            'id': n.id, 'vlan_id': n.vlan_id, 'cidr': n.cidr}
            for n in nets_db]

        nodes = [{'id': n.id, 'ip': n.ip, 'mac': n.mac, 'uid': n.id}
                 for n in cluster.nodes]

        message = {'method': 'verify_networks',
                   'respond_to': 'verify_networks_resp',
                   'args': {'task_uuid': task.uuid,
                            'networks': networks,
                            'nodes': nodes}}
        rpc.cast('naily', message)

        return json.dumps(
            TaskHandler.render(task),
            indent=4
        )


class ClusterAttributesHandler(JSONHandler):
    fields = (
        "editable",
    )

    def GET(self, cluster_id):
        web.header('Content-Type', 'application/json')
        cluster = web.ctx.orm.query(Cluster).get(int(cluster_id))
        if not cluster:
            return web.notfound()

        attrs = cluster.attributes
        if not attrs:
            raise web.internalerror("No attributes found!")

        return json.dumps(
            {
                "editable": attrs.editable
            },
            indent=4
        )

    def PUT(self, cluster_id):
        web.header('Content-Type', 'application/json')
        cluster = web.ctx.orm.query(Cluster).get(int(cluster_id))
        if not cluster:
            return web.notfound()

        attrs = cluster.attributes
        if not attrs:
            raise web.internalerror("No attributes found!")

        data = Attributes.validate(web.data())

        for key, value in data.iteritems():
            setattr(attrs, key, value)

        web.ctx.orm.add(attrs)
        web.ctx.orm.commit()

        return json.dumps(
            {
                "editable": attrs.editable
            },
            indent=4
        )
