#include <vulkan/vk_enum_string_helper.h>

extern "C" const char* vkResultToString(VkResult result)
{
    return string_VkResult(result);
}

VKAPI_ATTR VkResult VKAPI_CALL vkCreateDebugReportCallbackEXT(
    VkInstance                                  instance,
    const VkDebugReportCallbackCreateInfoEXT*   pCreateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkDebugReportCallbackEXT*                   pCallback)
{
    static auto func = (PFN_vkCreateDebugReportCallbackEXT)vkGetInstanceProcAddr(instance, "vkCreateDebugReportCallbackEXT");
    return func(instance, pCreateInfo, pAllocator, pCallback);
}

VKAPI_ATTR void VKAPI_CALL vkDestroyDebugReportCallbackEXT(
    VkInstance                                  instance,
    VkDebugReportCallbackEXT                    callback,
    const VkAllocationCallbacks*                pAllocator)
{
    static auto func = (PFN_vkDestroyDebugReportCallbackEXT)vkGetInstanceProcAddr(instance, "vkDestroyDebugReportCallbackEXT");
    func(instance, callback, pAllocator);
}
