const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const log = utility.log_scoped;

const Instance = @import("instance.zig").Instance;

pub const PhysicalDevice = struct {
    handle: c.VkPhysicalDevice = undefined,
    properties: c.VkPhysicalDeviceProperties = undefined,
    features: c.VkPhysicalDeviceFeatures = undefined,

    pub fn init(self: *PhysicalDevice, instance: *Instance, allocator: std.mem.Allocator) !void {
        errdefer self.deinit();

        self.selectPhysicalDevice(instance, allocator) catch {
            log.err("Failed to select physical device", .{});
            return error.FailedToSelectPhysicalDevice;
        };
    }

    pub fn deinit(self: *PhysicalDevice) void {
        // Physial device is owned by instance
        self.* = undefined;
    }

    fn selectPhysicalDevice(self: *PhysicalDevice, instance: *const Instance, allocator: std.mem.Allocator) !void {
        // Simplified physical device selection - select first that is dedictated GPU
        log.info("Selecting physical device...", .{});

        var physical_device_count: u32 = 0;
        try utility.checkResult(c.vkEnumeratePhysicalDevices.?(instance.handle, &physical_device_count, null));
        if (physical_device_count == 0) {
            log.err("Failed to find any physical devices", .{});
            return error.NoAvailableDevices;
        }

        const physical_devices = try allocator.alloc(c.VkPhysicalDevice, physical_device_count);
        defer allocator.free(physical_devices);
        try utility.checkResult(c.vkEnumeratePhysicalDevices.?(instance.handle, &physical_device_count, physical_devices.ptr));

        const PhysicalDeviceCandidate = struct {
            device: c.VkPhysicalDevice,
            properties: c.VkPhysicalDeviceProperties,
            features: c.VkPhysicalDeviceFeatures,
        };

        const physical_device_candidates = try allocator.alloc(PhysicalDeviceCandidate, physical_device_count);
        defer allocator.free(physical_device_candidates);

        for (physical_devices, 0..) |available_device, i| {
            physical_device_candidates[i].device = available_device;
            c.vkGetPhysicalDeviceProperties.?(available_device, &physical_device_candidates[i].properties);
            c.vkGetPhysicalDeviceFeatures.?(available_device, &physical_device_candidates[i].features);
            log.info("Available GPU: {s}", .{std.mem.sliceTo(&physical_device_candidates[i].properties.deviceName, 0)});
        }

        const DevicePrioritization = struct {
            fn lessThan(_: void, a: PhysicalDeviceCandidate, b: PhysicalDeviceCandidate) bool {
                return a.properties.deviceType > b.properties.deviceType; // Prefer discrete GPU over integrated GPU
            }
        };

        std.sort.insertion(PhysicalDeviceCandidate, physical_device_candidates, {}, DevicePrioritization.lessThan);

        self.handle = physical_device_candidates[0].device;
        self.properties = physical_device_candidates[0].properties;
        self.features = physical_device_candidates[0].features;

        log.info("Selected GPU: {s} (Driver version: {}.{}.{}, Vulkan support: {}.{}.{})", .{
            std.mem.sliceTo(&self.properties.deviceName, 0),
            c.VK_VERSION_MAJOR(self.properties.driverVersion),
            c.VK_VERSION_MINOR(self.properties.driverVersion),
            c.VK_VERSION_PATCH(self.properties.driverVersion),
            c.VK_VERSION_MAJOR(self.properties.apiVersion),
            c.VK_VERSION_MINOR(self.properties.apiVersion),
            c.VK_VERSION_PATCH(self.properties.apiVersion),
        });
    }
};
