#extension GL_EXT_nonuniform_qualifier : enable

layout(push_constant) uniform PushConstant {
    uint ubo_id;
};

layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo[];
