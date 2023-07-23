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

# Write header
file.write(struct.pack('I', 3001199146)) # Magic
file.write(struct.pack('I', 1)) # Version

# Write vertices
class Attribute(enum.Flag): 
    POSITION = enum.auto()
    NORMAL = enum.auto()
    COLOR = enum.auto()
    UV = enum.auto()

print("Vertex attributes: Position, Normal, Color")
attribute_flags = Attribute.POSITION | Attribute.NORMAL | Attribute.COLOR
file.write(struct.pack('I', attribute_flags.value)) # Vertex attributes

print("Writing " + str(len(mesh.vertices)) + " vertices...")
file.write(struct.pack('I', len(mesh.vertices))) # Vertex count

for vertex in mesh.vertices:
    file.write(struct.pack('fff', vertex.co.x, vertex.co.y, vertex.co.z))

for vertex in mesh.vertices:
    file.write(struct.pack('fff', vertex.normal.x, vertex.normal.y, vertex.normal.z))

for vertex in mesh.vertices:
    file.write(struct.pack('ffff', 1.0, 1.0, 1.0, 1.0))

# Write indices
if len(mesh.vertices) < 65536:
    print("Index type: uint16")
    index_type_bytes = 2
    index_pack = 'HHH'
else:
    print("Index type: uint32")
    index_type_bytes = 4
    index_pack = 'III'

file.write(struct.pack('I', index_type_bytes)) # Index type bytes
file.write(struct.pack('I', len(mesh.polygons) * 3)) # Index count
print("Writing " + str(len(mesh.polygons)) + " polygons...")

for face in mesh.polygons:
    file.write(struct.pack(index_pack, face.vertices[0], face.vertices[1], face.vertices[2]))

# Cleanup
file.close()
print("Done!")
