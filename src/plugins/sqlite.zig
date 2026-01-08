//! SQLite Plugin
//!
//! Local database storage using SQLite.
//! Provides a simple API for SQL operations.

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Error = error{
    OpenFailed,
    PrepareFailed,
    BindFailed,
    StepFailed,
    ColumnOutOfRange,
    NotADatabase,
    Busy,
    Locked,
    NoMemory,
    ReadOnly,
    Constraint,
    Mismatch,
    Misuse,
    NotInitialized,
    Unknown,
};

fn sqliteError(code: c_int) Error {
    return switch (code) {
        c.SQLITE_CANTOPEN => Error.OpenFailed,
        c.SQLITE_NOTADB => Error.NotADatabase,
        c.SQLITE_BUSY => Error.Busy,
        c.SQLITE_LOCKED => Error.Locked,
        c.SQLITE_NOMEM => Error.NoMemory,
        c.SQLITE_READONLY => Error.ReadOnly,
        c.SQLITE_CONSTRAINT => Error.Constraint,
        c.SQLITE_MISMATCH => Error.Mismatch,
        c.SQLITE_MISUSE => Error.Misuse,
        else => Error.Unknown,
    };
}

pub const Value = union(enum) {
    null_value,
    integer: i64,
    float: f64,
    text: []const u8,
    blob: []const u8,

    pub fn format(self: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .null_value => try writer.writeAll("NULL"),
            .integer => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .text => |v| try writer.print("\"{s}\"", .{v}),
            .blob => |v| try writer.print("<blob {d} bytes>", .{v.len}),
        }
    }
};

pub const Row = struct {
    values: []Value,
    columns: [][]const u8,
    allocator: Allocator,

    pub fn deinit(self: *Row) void {
        for (self.values) |val| {
            switch (val) {
                .text => |t| self.allocator.free(t),
                .blob => |b| self.allocator.free(b),
                else => {},
            }
        }
        self.allocator.free(self.values);
        for (self.columns) |col| {
            self.allocator.free(col);
        }
        self.allocator.free(self.columns);
    }

    pub fn get(self: *const Row, index: usize) ?Value {
        if (index >= self.values.len) return null;
        return self.values[index];
    }

    pub fn getByName(self: *const Row, name: []const u8) ?Value {
        for (self.columns, 0..) |col, i| {
            if (std.mem.eql(u8, col, name)) {
                return self.values[i];
            }
        }
        return null;
    }
};

pub const Statement = struct {
    stmt: *c.sqlite3_stmt,
    db: *Database,
    allocator: Allocator,

    pub fn deinit(self: *Statement) void {
        _ = c.sqlite3_finalize(self.stmt);
    }

    pub fn bind(self: *Statement, index: usize, value: anytype) !void {
        const idx: c_int = @intCast(index + 1); // SQLite is 1-indexed
        const rc = switch (@TypeOf(value)) {
            i32, i64, usize, comptime_int => c.sqlite3_bind_int64(self.stmt, idx, @intCast(value)),
            f32, f64 => c.sqlite3_bind_double(self.stmt, idx, @floatCast(value)),
            []const u8 => c.sqlite3_bind_text(self.stmt, idx, value.ptr, @intCast(value.len), c.SQLITE_TRANSIENT),
            @TypeOf(null) => c.sqlite3_bind_null(self.stmt, idx),
            else => @compileError("Unsupported bind type"),
        };
        if (rc != c.SQLITE_OK) return Error.BindFailed;
    }

    pub fn step(self: *Statement) !bool {
        const rc = c.sqlite3_step(self.stmt);
        if (rc == c.SQLITE_ROW) return true;
        if (rc == c.SQLITE_DONE) return false;
        return sqliteError(rc);
    }

    pub fn reset(self: *Statement) void {
        _ = c.sqlite3_reset(self.stmt);
        _ = c.sqlite3_clear_bindings(self.stmt);
    }

    pub fn columnCount(self: *Statement) usize {
        return @intCast(c.sqlite3_column_count(self.stmt));
    }

    pub fn columnName(self: *Statement, index: usize) []const u8 {
        const name = c.sqlite3_column_name(self.stmt, @intCast(index));
        return std.mem.span(name);
    }

    pub fn column(self: *Statement, index: usize) !Value {
        const idx: c_int = @intCast(index);
        const col_type = c.sqlite3_column_type(self.stmt, idx);

        return switch (col_type) {
            c.SQLITE_NULL => Value{ .null_value = {} },
            c.SQLITE_INTEGER => Value{ .integer = c.sqlite3_column_int64(self.stmt, idx) },
            c.SQLITE_FLOAT => Value{ .float = c.sqlite3_column_double(self.stmt, idx) },
            c.SQLITE_TEXT => blk: {
                const ptr = c.sqlite3_column_text(self.stmt, idx);
                const len: usize = @intCast(c.sqlite3_column_bytes(self.stmt, idx));
                const text = try self.allocator.dupe(u8, ptr[0..len]);
                break :blk Value{ .text = text };
            },
            c.SQLITE_BLOB => blk: {
                const ptr: [*]const u8 = @ptrCast(c.sqlite3_column_blob(self.stmt, idx));
                const len: usize = @intCast(c.sqlite3_column_bytes(self.stmt, idx));
                const blob = try self.allocator.dupe(u8, ptr[0..len]);
                break :blk Value{ .blob = blob };
            },
            else => Value{ .null_value = {} },
        };
    }

    pub fn row(self: *Statement) !Row {
        const count = self.columnCount();
        var values = try self.allocator.alloc(Value, count);
        var columns = try self.allocator.alloc([]const u8, count);

        for (0..count) |i| {
            values[i] = try self.column(i);
            columns[i] = try self.allocator.dupe(u8, self.columnName(i));
        }

        return Row{
            .values = values,
            .columns = columns,
            .allocator = self.allocator,
        };
    }
};

pub const Database = struct {
    db: *c.sqlite3,
    allocator: Allocator,

    const Self = @This();

    pub fn open(allocator: Allocator, path: []const u8) !Self {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path_z, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| _ = c.sqlite3_close(d);
            return sqliteError(rc);
        }

        return Self{
            .db = db.?,
            .allocator = allocator,
        };
    }

    pub fn openInMemory(allocator: Allocator) !Self {
        return open(allocator, ":memory:");
    }

    pub fn close(self: *Self) void {
        _ = c.sqlite3_close(self.db);
    }

    pub fn prepare(self: *Self, sql: []const u8) !Statement {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql_z, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) {
            return Error.PrepareFailed;
        }

        return Statement{
            .stmt = stmt.?,
            .db = self,
            .allocator = self.allocator,
        };
    }

    /// Execute SQL without returning results (CREATE, INSERT, UPDATE, DELETE)
    pub fn exec(self: *Self, sql: []const u8) !void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var err_msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql_z, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg) |msg| {
                std.debug.print("[sqlite] Error: {s}\n", .{msg});
                c.sqlite3_free(msg);
            }
            return sqliteError(rc);
        }
    }

    /// Execute SQL with parameters
    pub fn run(self: *Self, sql: []const u8, params: anytype) !void {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();

        inline for (params, 0..) |param, i| {
            try stmt.bind(i, param);
        }

        _ = try stmt.step();
    }

    /// Query and return all rows
    pub fn all(self: *Self, allocator: Allocator, sql: []const u8, params: anytype) ![]Row {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();

        inline for (params, 0..) |param, i| {
            try stmt.bind(i, param);
        }

        var rows = std.ArrayList(Row).init(allocator);
        errdefer {
            for (rows.items) |*r| r.deinit();
            rows.deinit();
        }

        while (try stmt.step()) {
            const r = try stmt.row();
            try rows.append(r);
        }

        return rows.toOwnedSlice();
    }

    /// Query and return first row
    pub fn get(self: *Self, sql: []const u8, params: anytype) !?Row {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();

        inline for (params, 0..) |param, i| {
            try stmt.bind(i, param);
        }

        if (try stmt.step()) {
            return try stmt.row();
        }
        return null;
    }

    /// Get last insert rowid
    pub fn lastInsertRowId(self: *Self) i64 {
        return c.sqlite3_last_insert_rowid(self.db);
    }

    /// Get number of rows changed by last statement
    pub fn changes(self: *Self) i32 {
        return c.sqlite3_changes(self.db);
    }

    /// Get last error message
    pub fn errorMessage(self: *Self) []const u8 {
        return std.mem.span(c.sqlite3_errmsg(self.db));
    }
};

// Test
test "sqlite basic operations" {
    const allocator = std.testing.allocator;

    var db = try Database.openInMemory(allocator);
    defer db.close();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)");
    try db.run("INSERT INTO users (name, age) VALUES (?, ?)", .{ "Alice", 30 });
    try db.run("INSERT INTO users (name, age) VALUES (?, ?)", .{ "Bob", 25 });

    const rows = try db.all(allocator, "SELECT * FROM users WHERE age > ?", .{20});
    defer {
        for (rows) |*r| {
            var row_mut = r.*;
            row_mut.deinit();
        }
        allocator.free(rows);
    }

    try std.testing.expectEqual(@as(usize, 2), rows.len);
}
