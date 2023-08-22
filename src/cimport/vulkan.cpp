#include <vulkan/vk_enum_string_helper.h>

extern "C" const char* vkResultToString(VkResult result)
{
    return string_VkResult(result);
}
