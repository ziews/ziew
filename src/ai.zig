//! AI Module - Local LLM inference via llama.cpp
//!
//! Provides text generation capabilities using local models.
//! Build with -Dai=true (requires llama.cpp installed)
//!
//! ## Installation
//!
//! llama.cpp uses CMake:
//!   git clone https://github.com/ggerganov/llama.cpp
//!   cd llama.cpp
//!   cmake -B build
//!   cmake --build build
//!   sudo cmake --install build
//!
//! ## Models
//!
//! Download GGUF models from HuggingFace:
//!   https://huggingface.co/models?search=gguf
//!
//! Recommended small models:
//!   - TinyLlama 1.1B (~600MB)
//!   - Llama 3.2 1B (~700MB)
//!   - Phi-3 mini 3.8B (~2GB)

const std = @import("std");

const c = @cImport({
    @cInclude("llama.h");
});

pub const AiError = error{
    InitFailed,
    ModelLoadFailed,
    ContextCreateFailed,
    TokenizeFailed,
    DecodeFailed,
    OutOfMemory,
};

/// AI inference engine
pub const Ai = struct {
    allocator: std.mem.Allocator,
    model: *c.llama_model,
    ctx: *c.llama_context,
    sampler: *c.llama_sampler,
    vocab: *const c.llama_vocab,

    const Self = @This();

    /// Initialize AI with a model file
    pub fn init(allocator: std.mem.Allocator, model_path: []const u8) !Self {
        // Initialize backend
        c.llama_backend_init();

        // Load model
        const path_z = try allocator.dupeZ(u8, model_path);
        defer allocator.free(path_z);

        var model_params = c.llama_model_default_params();
        model_params.n_gpu_layers = 0; // CPU only for now

        const model = c.llama_model_load_from_file(path_z.ptr, model_params) orelse {
            return AiError.ModelLoadFailed;
        };

        // Get vocab
        const vocab = c.llama_model_get_vocab(model) orelse {
            c.llama_model_free(model);
            return AiError.ModelLoadFailed;
        };

        // Create context
        var ctx_params = c.llama_context_default_params();
        ctx_params.n_ctx = 2048;
        ctx_params.n_batch = 512;

        const ctx = c.llama_init_from_model(model, ctx_params) orelse {
            c.llama_model_free(model);
            return AiError.ContextCreateFailed;
        };

        // Create sampler chain
        const sampler = c.llama_sampler_chain_init(c.llama_sampler_chain_default_params());
        c.llama_sampler_chain_add(sampler, c.llama_sampler_init_temp(0.7));
        c.llama_sampler_chain_add(sampler, c.llama_sampler_init_dist(c.LLAMA_DEFAULT_SEED));

        return Self{
            .allocator = allocator,
            .model = model,
            .ctx = ctx,
            .sampler = sampler,
            .vocab = vocab,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        c.llama_sampler_free(self.sampler);
        c.llama_free(self.ctx);
        c.llama_model_free(self.model);
        c.llama_backend_free();
    }

    /// Generate text completion
    pub fn complete(self: *Self, prompt: []const u8, max_tokens: u32) ![]const u8 {
        // Tokenize prompt
        const prompt_z = try self.allocator.dupeZ(u8, prompt);
        defer self.allocator.free(prompt_z);

        const max_prompt_tokens = 1024;
        var tokens: [max_prompt_tokens]c.llama_token = undefined;

        const n_prompt_tokens = c.llama_tokenize(
            self.vocab,
            prompt_z.ptr,
            @intCast(prompt.len),
            &tokens,
            max_prompt_tokens,
            true, // add BOS
            true, // parse special
        );

        if (n_prompt_tokens < 0) {
            return AiError.TokenizeFailed;
        }

        // Create batch for prompt
        var batch = c.llama_batch_init(512, 0, 1);
        defer c.llama_batch_free(batch);

        // Add prompt tokens to batch
        for (0..@intCast(n_prompt_tokens)) |i| {
            batch.token[i] = tokens[i];
            batch.pos[i] = @intCast(i);
            batch.n_seq_id[i] = 1;
            batch.seq_id[i][0] = 0;
            batch.logits[i] = 0;
        }
        batch.logits[@intCast(n_prompt_tokens - 1)] = 1; // Enable logits for last token
        batch.n_tokens = n_prompt_tokens;

        // Decode prompt
        if (c.llama_decode(self.ctx, batch) != 0) {
            return AiError.DecodeFailed;
        }

        // Generate tokens
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        var n_cur: i32 = n_prompt_tokens;
        const n_max: i32 = n_prompt_tokens + @as(i32, @intCast(max_tokens));

        while (n_cur < n_max) {
            // Sample next token
            const new_token = c.llama_sampler_sample(self.sampler, self.ctx, -1);

            // Check for end of generation
            if (c.llama_vocab_is_eog(self.vocab, new_token)) {
                break;
            }

            // Convert token to text
            var buf: [256]u8 = undefined;
            const n = c.llama_token_to_piece(self.vocab, new_token, &buf, buf.len, 0, true);
            if (n > 0) {
                try output.appendSlice(buf[0..@intCast(n)]);
            }

            // Prepare next batch
            batch.token[0] = new_token;
            batch.pos[0] = n_cur;
            batch.n_seq_id[0] = 1;
            batch.seq_id[0][0] = 0;
            batch.logits[0] = 1;
            batch.n_tokens = 1;

            n_cur += 1;

            if (c.llama_decode(self.ctx, batch) != 0) {
                return AiError.DecodeFailed;
            }

            c.llama_sampler_reset(self.sampler);
        }

        return output.toOwnedSlice();
    }

    /// Generate text with streaming callback
    /// The callback receives each token and an optional context pointer
    pub fn stream(
        self: *Self,
        prompt: []const u8,
        max_tokens: u32,
        callback: *const fn ([]const u8, ?*anyopaque) void,
        ctx: ?*anyopaque,
    ) !void {
        // Clear memory/KV cache for new conversation
        c.llama_memory_clear(c.llama_get_memory(self.ctx), true);

        // Tokenize prompt
        const prompt_z = try self.allocator.dupeZ(u8, prompt);
        defer self.allocator.free(prompt_z);

        const max_prompt_tokens = 1024;
        var tokens: [max_prompt_tokens]c.llama_token = undefined;

        const n_prompt_tokens = c.llama_tokenize(
            self.vocab,
            prompt_z.ptr,
            @intCast(prompt.len),
            &tokens,
            max_prompt_tokens,
            true,
            true,
        );

        if (n_prompt_tokens < 0) {
            return AiError.TokenizeFailed;
        }

        // Create batch
        var batch = c.llama_batch_init(512, 0, 1);
        defer c.llama_batch_free(batch);

        // Add prompt tokens
        for (0..@intCast(n_prompt_tokens)) |i| {
            batch.token[i] = tokens[i];
            batch.pos[i] = @intCast(i);
            batch.n_seq_id[i] = 1;
            batch.seq_id[i][0] = 0;
            batch.logits[i] = 0;
        }
        batch.logits[@intCast(n_prompt_tokens - 1)] = 1;
        batch.n_tokens = n_prompt_tokens;

        if (c.llama_decode(self.ctx, batch) != 0) {
            return AiError.DecodeFailed;
        }

        // Generate and stream tokens
        var n_cur: i32 = n_prompt_tokens;
        const n_max: i32 = n_prompt_tokens + @as(i32, @intCast(max_tokens));

        while (n_cur < n_max) {
            const new_token = c.llama_sampler_sample(self.sampler, self.ctx, -1);

            if (c.llama_vocab_is_eog(self.vocab, new_token)) {
                break;
            }

            // Convert and stream
            var buf: [256]u8 = undefined;
            const n = c.llama_token_to_piece(self.vocab, new_token, &buf, buf.len, 0, true);
            if (n > 0) {
                callback(buf[0..@intCast(n)], ctx);
            }

            // Next iteration
            batch.token[0] = new_token;
            batch.pos[0] = n_cur;
            batch.n_seq_id[0] = 1;
            batch.seq_id[0][0] = 0;
            batch.logits[0] = 1;
            batch.n_tokens = 1;

            n_cur += 1;

            if (c.llama_decode(self.ctx, batch) != 0) {
                return AiError.DecodeFailed;
            }

            c.llama_sampler_reset(self.sampler);
        }
    }

    /// Clear the KV cache (for new conversations)
    pub fn clear(self: *Self) void {
        c.llama_memory_clear(c.llama_get_memory(self.ctx), true);
    }
};

/// Get the models directory path (~/.ziew/models/)
pub fn getModelsDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return std.fmt.allocPrint(allocator, "{s}/.ziew/models", .{home});
}

/// Ensure the models directory exists
pub fn ensureModelsDir(allocator: std.mem.Allocator) !void {
    const models_dir = try getModelsDir(allocator);
    defer allocator.free(models_dir);

    // Create ~/.ziew if it doesn't exist
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const ziew_dir = try std.fmt.allocPrint(allocator, "{s}/.ziew", .{home});
    defer allocator.free(ziew_dir);

    std.fs.makeDirAbsolute(ziew_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create ~/.ziew/models if it doesn't exist
    std.fs.makeDirAbsolute(models_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

/// List available models in ~/.ziew/models/
/// Returns a list of .gguf filenames (caller must free each string and the slice)
pub fn listModels(allocator: std.mem.Allocator) ![][]const u8 {
    const models_dir = try getModelsDir(allocator);
    defer allocator.free(models_dir);

    var models = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (models.items) |m| allocator.free(m);
        models.deinit();
    }

    var dir = std.fs.openDirAbsolute(models_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            return models.toOwnedSlice();
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const name = entry.name;
            if (std.mem.endsWith(u8, name, ".gguf")) {
                const copy = try allocator.dupe(u8, name);
                try models.append(copy);
            }
        }
    }

    return models.toOwnedSlice();
}

/// Find the default model (first .gguf file in ~/.ziew/models/)
/// Returns the full path to the model, or null if none found
pub fn findDefaultModel(allocator: std.mem.Allocator) !?[]const u8 {
    const models = try listModels(allocator);
    defer {
        for (models) |m| allocator.free(m);
        allocator.free(models);
    }

    if (models.len == 0) {
        return null;
    }

    // Return full path to first model
    const models_dir = try getModelsDir(allocator);
    defer allocator.free(models_dir);

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ models_dir, models[0] });
    return path;
}

/// Get full path for a model by name
/// If name contains '/', treats it as a path, otherwise looks in ~/.ziew/models/
pub fn getModelPath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // If it's already a path, return as-is
    if (std.mem.indexOf(u8, name, "/") != null) {
        return allocator.dupe(u8, name);
    }

    // Otherwise, look in models directory
    const models_dir = try getModelsDir(allocator);
    defer allocator.free(models_dir);

    // Add .gguf extension if not present
    if (std.mem.endsWith(u8, name, ".gguf")) {
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ models_dir, name });
    } else {
        return std.fmt.allocPrint(allocator, "{s}/{s}.gguf", .{ models_dir, name });
    }
}

/// Deprecated: use getModelsDir instead
pub fn getDefaultModelPath(allocator: std.mem.Allocator) ![]const u8 {
    return getModelsDir(allocator);
}
