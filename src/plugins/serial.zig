//! Serial Port Plugin
//!
//! Serial port communication for hardware projects.
//!
//! Linux/macOS: Uses POSIX termios
//! Windows: Uses Win32 serial API (TODO)

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const Allocator = std.mem.Allocator;

pub const SerialError = error{
    OpenFailed,
    ConfigFailed,
    ReadFailed,
    WriteFailed,
    NotSupported,
    NotImplemented,
    InvalidBaudRate,
};

pub const BaudRate = enum(u32) {
    b1200 = 1200,
    b2400 = 2400,
    b4800 = 4800,
    b9600 = 9600,
    b19200 = 19200,
    b38400 = 38400,
    b57600 = 57600,
    b115200 = 115200,
    b230400 = 230400,
    b460800 = 460800,
    b921600 = 921600,
};

pub const DataBits = enum { five, six, seven, eight };
pub const Parity = enum { none, odd, even };
pub const StopBits = enum { one, two };
pub const FlowControl = enum { none, hardware, software };

pub const SerialConfig = struct {
    baud_rate: BaudRate = .b9600,
    data_bits: DataBits = .eight,
    parity: Parity = .none,
    stop_bits: StopBits = .one,
    flow_control: FlowControl = .none,
};

pub const PortInfo = struct {
    path: []const u8,
    name: []const u8,
    manufacturer: ?[]const u8 = null,
    product: ?[]const u8 = null,
};

// POSIX implementation (Linux/macOS)
const posix_impl = struct {
    const c = @cImport({
        @cInclude("termios.h");
        @cInclude("fcntl.h");
        @cInclude("unistd.h");
        @cInclude("sys/ioctl.h");
        @cInclude("dirent.h");
    });

    pub const SerialPort = struct {
        fd: posix.fd_t,
        allocator: Allocator,
        path: []const u8,
        original_termios: c.termios,

        pub fn open(allocator: Allocator, path: []const u8, config: SerialConfig) !SerialPort {
            const path_z = try allocator.dupeZ(u8, path);
            defer allocator.free(path_z);

            const fd = posix.open(path_z, .{
                .ACCMODE = .RDWR,
                .NOCTTY = true,
                .NONBLOCK = true,
            }, 0) catch return SerialError.OpenFailed;
            errdefer posix.close(fd);

            // Get current settings
            var tty: c.termios = undefined;
            if (c.tcgetattr(fd, &tty) != 0) {
                return SerialError.ConfigFailed;
            }

            const original = tty;

            // Set raw mode
            c.cfmakeraw(&tty);

            // Configure baud rate
            const speed = baudToSpeed(config.baud_rate);
            _ = c.cfsetispeed(&tty, speed);
            _ = c.cfsetospeed(&tty, speed);

            // Configure data bits
            tty.c_cflag &= ~@as(c_uint, c.CSIZE);
            tty.c_cflag |= switch (config.data_bits) {
                .five => c.CS5,
                .six => c.CS6,
                .seven => c.CS7,
                .eight => c.CS8,
            };

            // Configure parity
            switch (config.parity) {
                .none => {
                    tty.c_cflag &= ~@as(c_uint, c.PARENB);
                },
                .odd => {
                    tty.c_cflag |= c.PARENB | c.PARODD;
                },
                .even => {
                    tty.c_cflag |= c.PARENB;
                    tty.c_cflag &= ~@as(c_uint, c.PARODD);
                },
            }

            // Configure stop bits
            if (config.stop_bits == .two) {
                tty.c_cflag |= c.CSTOPB;
            } else {
                tty.c_cflag &= ~@as(c_uint, c.CSTOPB);
            }

            // Configure flow control
            switch (config.flow_control) {
                .none => {
                    tty.c_cflag &= ~@as(c_uint, c.CRTSCTS);
                    tty.c_iflag &= ~@as(c_uint, c.IXON | c.IXOFF | c.IXANY);
                },
                .hardware => {
                    tty.c_cflag |= c.CRTSCTS;
                    tty.c_iflag &= ~@as(c_uint, c.IXON | c.IXOFF | c.IXANY);
                },
                .software => {
                    tty.c_cflag &= ~@as(c_uint, c.CRTSCTS);
                    tty.c_iflag |= c.IXON | c.IXOFF;
                },
            }

            // Enable reading
            tty.c_cflag |= c.CREAD | c.CLOCAL;

            // Set VMIN and VTIME for non-blocking reads
            tty.c_cc[c.VMIN] = 0;
            tty.c_cc[c.VTIME] = 1; // 100ms timeout

            // Apply settings
            if (c.tcsetattr(fd, c.TCSANOW, &tty) != 0) {
                return SerialError.ConfigFailed;
            }

            // Clear non-blocking flag for normal operation
            const flags = std.os.linux.fcntl(fd, std.os.linux.F.GETFL, @as(u32, 0));
            _ = std.os.linux.fcntl(fd, std.os.linux.F.SETFL, flags & ~@as(u32, std.os.linux.O.NONBLOCK));

            return SerialPort{
                .fd = fd,
                .allocator = allocator,
                .path = try allocator.dupe(u8, path),
                .original_termios = original,
            };
        }

        pub fn close(self: *SerialPort) void {
            // Restore original settings
            _ = c.tcsetattr(self.fd, c.TCSANOW, &self.original_termios);
            posix.close(self.fd);
            self.allocator.free(self.path);
        }

        pub fn read(self: *SerialPort, buffer: []u8) !usize {
            const n = posix.read(self.fd, buffer) catch |err| {
                if (err == error.WouldBlock) return 0;
                return SerialError.ReadFailed;
            };
            return n;
        }

        pub fn write(self: *SerialPort, data: []const u8) !usize {
            const n = posix.write(self.fd, data) catch return SerialError.WriteFailed;
            return n;
        }

        pub fn flush(self: *SerialPort) void {
            _ = c.tcdrain(self.fd);
        }

        pub fn available(self: *SerialPort) usize {
            var bytes: c_int = 0;
            _ = c.ioctl(self.fd, c.FIONREAD, &bytes);
            return @intCast(@max(0, bytes));
        }

        pub fn setDTR(self: *SerialPort, value: bool) void {
            var status: c_int = 0;
            _ = c.ioctl(self.fd, c.TIOCMGET, &status);
            if (value) {
                status |= c.TIOCM_DTR;
            } else {
                status &= ~@as(c_int, c.TIOCM_DTR);
            }
            _ = c.ioctl(self.fd, c.TIOCMSET, &status);
        }

        pub fn setRTS(self: *SerialPort, value: bool) void {
            var status: c_int = 0;
            _ = c.ioctl(self.fd, c.TIOCMGET, &status);
            if (value) {
                status |= c.TIOCM_RTS;
            } else {
                status &= ~@as(c_int, c.TIOCM_RTS);
            }
            _ = c.ioctl(self.fd, c.TIOCMSET, &status);
        }
    };

    fn baudToSpeed(baud: BaudRate) c.speed_t {
        return switch (baud) {
            .b1200 => c.B1200,
            .b2400 => c.B2400,
            .b4800 => c.B4800,
            .b9600 => c.B9600,
            .b19200 => c.B19200,
            .b38400 => c.B38400,
            .b57600 => c.B57600,
            .b115200 => c.B115200,
            .b230400 => c.B230400,
            .b460800 => c.B460800,
            .b921600 => c.B921600,
        };
    }

    pub fn listPorts(allocator: Allocator) ![]PortInfo {
        var ports = std.ArrayList(PortInfo).init(allocator);
        errdefer {
            for (ports.items) |port| {
                allocator.free(port.path);
                allocator.free(port.name);
            }
            ports.deinit();
        }

        // Check /dev/ttyUSB* and /dev/ttyACM* (common on Linux)
        const prefixes = [_][]const u8{ "/dev/ttyUSB", "/dev/ttyACM", "/dev/ttyS" };

        for (prefixes) |prefix| {
            var i: usize = 0;
            while (i < 16) : (i += 1) {
                var path_buf: [64]u8 = undefined;
                const path = std.fmt.bufPrint(&path_buf, "{s}{d}", .{ prefix, i }) catch continue;

                // Check if device exists
                std.fs.accessAbsolute(path, .{}) catch continue;

                const name = if (std.mem.startsWith(u8, path, "/dev/ttyUSB"))
                    "USB Serial"
                else if (std.mem.startsWith(u8, path, "/dev/ttyACM"))
                    "USB ACM"
                else
                    "Serial Port";

                try ports.append(.{
                    .path = try allocator.dupe(u8, path),
                    .name = try allocator.dupe(u8, name),
                });
            }
        }

        return ports.toOwnedSlice();
    }
};

// Public API

pub const SerialPort = switch (builtin.os.tag) {
    .linux, .macos => posix_impl.SerialPort,
    else => struct {
        pub fn open(_: Allocator, _: []const u8, _: SerialConfig) !@This() {
            return SerialError.NotImplemented;
        }
        pub fn close(_: *@This()) void {}
        pub fn read(_: *@This(), _: []u8) !usize {
            return 0;
        }
        pub fn write(_: *@This(), _: []const u8) !usize {
            return 0;
        }
        pub fn flush(_: *@This()) void {}
        pub fn available(_: *@This()) usize {
            return 0;
        }
    },
};

/// Open a serial port
pub fn open(allocator: Allocator, path: []const u8, config: SerialConfig) !SerialPort {
    return SerialPort.open(allocator, path, config);
}

/// List available serial ports
pub fn listPorts(allocator: Allocator) ![]PortInfo {
    switch (builtin.os.tag) {
        .linux, .macos => return posix_impl.listPorts(allocator),
        else => return &[_]PortInfo{},
    }
}
