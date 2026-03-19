"""TaoBench 3-node profile.

Creates:
- 1 server node
- 2 client nodes
- private LAN with static IPs
"""

import geni.portal as portal
import geni.rspec.pg as rspec

pc = portal.Context()
request = pc.makeRequestRSpec()

pc.defineParameter(
    "hardware_type",
    "Hardware type for all nodes",
    portal.ParameterType.NODETYPE,
    "c6220"
)

pc.defineParameter(
    "disk_image",
    "Disk image / OS for all nodes",
    portal.ParameterType.IMAGE,
    "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU22-64-STD"
)

params = pc.bindParameters()

# Server
server = request.RawPC("server")
server.hardware_type = params.hardware_type
server.disk_image = params.disk_image

# Client 1
client1 = request.RawPC("client1")
client1.hardware_type = params.hardware_type
client1.disk_image = params.disk_image

# Client 2
client2 = request.RawPC("client2")
client2.hardware_type = params.hardware_type
client2.disk_image = params.disk_image

# Private LAN
lan = request.LAN("bench-lan")

iface_s = server.addInterface("if0")
iface_s.addAddress(rspec.IPv4Address("192.168.1.10", "255.255.255.0"))
lan.addInterface(iface_s)

iface_c1 = client1.addInterface("if0")
iface_c1.addAddress(rspec.IPv4Address("192.168.1.11", "255.255.255.0"))
lan.addInterface(iface_c1)

iface_c2 = client2.addInterface("if0")
iface_c2.addAddress(rspec.IPv4Address("192.168.1.12", "255.255.255.0"))
lan.addInterface(iface_c2)

pc.printRequestRSpec(request)