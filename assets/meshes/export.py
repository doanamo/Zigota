# Example usage: blender ".\assets\meshes\cube.blend" -b -P ".\assets\meshes\export.py" -- ".\deploy\data\meshes\cube.bin"
#
# Binary format:
#   Header:
#     Magic: uint32
#     Version: uint32
#   Vertices:
#     Vertex attributes: uint32 
#     Vertex count: uint32
#     Per vertex attribute data: array
#   Indices:
#     Index type bytes: uint32
#     Index count: uint32
#     Index data: array

import enum
import struct
import sys
import os
import bpy

# Parse arguments
args = sys.argv[sys.argv.index("--") + 1:]

if len(args) < 1:
    print("Error: No output path specified")
    exit(1)

output_path = args[0]
print("Output path: " + output_path)

# Find mesh
mesh = None
for object in bpy.data.objects:
    if object.type == 'MESH':
        print("Found mesh: " + object.name)
        object_evaluated = object.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = object_evaluated.to_mesh()
        break

if mesh is None:
    print("Error: Mesh not found in scene")
    exit(1)

# Open output file
os.makedirs(os.path.dirname(output_path), exist_ok=True)
file = open(output_path, "wb")

# Write file header
file.write(struct.pack('I', 3001199146)) # Magic
file.write(struct.pack('I', 2)) # Version

# Write vertices header
has_color_attribute = len(mesh.color_attributes) > 0
has_uv_attribute = len(mesh.uv_layers) > 0

class Attribute(enum.Flag): 
    POSITION = enum.auto()
    NORMAL = enum.auto()
    COLOR = enum.auto()
    UV = enum.auto()

attribute_flags = Attribute.POSITION | Attribute.NORMAL

if has_color_attribute:
    print("Found color attributes")
    attribute_flags |= Attribute.COLOR

if has_uv_attribute:
    print("Found UV attributes")
    attribute_flags |= Attribute.UV

vertex_count = len(mesh.vertices)
file.write(struct.pack('I', attribute_flags.value))
file.write(struct.pack('I', vertex_count))

# Write vertex data
print("Writing " + str(vertex_count) + " vertices...")

for vertex in mesh.vertices:
    file.write(struct.pack('fff', vertex.co.x, vertex.co.y, vertex.co.z))

for vertex in mesh.vertices:
    file.write(struct.pack('fff', vertex.normal.x, vertex.normal.y, vertex.normal.z))

if has_color_attribute:
    for index, vertex in enumerate(mesh.vertices):
        color = mesh.color_attributes[0].data[index].color
        file.write(struct.pack('BBBB',
            int(color[0] * 255 + 0.5),
            int(color[1] * 255 + 0.5),
            int(color[2] * 255 + 0.5),
            int(color[3] * 255 + 0.5)))

# Write indices header
if len(mesh.vertices) < 65536:
    print("Index type: uint16")
    index_type_bytes = 2
    index_pack = 'HHH'
else:
    print("Index type: uint32")
    index_type_bytes = 4
    index_pack = 'III'

index_count = len(mesh.polygons) * 3
file.write(struct.pack('I', index_type_bytes))
file.write(struct.pack('I', index_count))

# Write index data
print("Writing " + str(index_count) + " indices...")

for face in mesh.polygons:
    file.write(struct.pack(index_pack, face.vertices[0], face.vertices[1], face.vertices[2]))

# Cleanup
file.close()
print("Done!")
