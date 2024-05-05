const std = @import("std");
const json = @import("evil-json");

const Uri = std.Uri;

const http = std.http;
const Client = std.http.Client;
const RequestOptions = Client.RequestOptions;

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

pub fn main() !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    var trivia_provider = TriviaProvider(20).init(allocator);

    while (true) {
        if (trivia_provider.next()) |trivia| {
            var answers: [4][]const u8 = trivia.incorrect_answers ++ .{trivia.correct_answer};

            try stdout.print("\n{s}\n", .{trivia.question});
            std.rand.shuffle(random, []const u8, answers[0..]);

            for (0.., answers) |choice, answer| {
                try stdout.print("({d}) {s}\n", .{ choice, answer });
            }

            while (true) {
                try stdout.print("Your answer: ", .{});

                var buf: [3]u8 = undefined;
                const input = stdin.readUntilDelimiterOrEof(&buf, '\n') catch "";

                if (input == null) {
                    try stdout.print("\nError: Couldn't take input.\n", .{});
                    return;
                }
                if (input.?.len < 2) {
                    try stdout.print("Answer with a number between 0 and 3!\n", .{});
                    continue;
                }

                const index: ?usize = std.fmt.parseInt(
                    usize,
                    input.?[0 .. input.?.len - 1],
                    10,
                ) catch null;
                if (index == null or 4 <= index.?) {
                    try stdout.print("Answer with a number between 0 and 3!\n", .{});
                    continue;
                }

                if (std.mem.eql(u8, answers[index.?], trivia.correct_answer)) {
                    try stdout.print("Good!\n", .{});
                    break;
                } else {
                    try stdout.print("Wrong: It is {s}\n", .{trivia.correct_answer});
                    break;
                }
            }
        } else |_| {
            try stdout.print("\nThere was some problem getting the trivia, retrying...\n", .{});
        }
    }
}

const Trivia = struct {
    question: []const u8,
    correct_answer: []const u8,
    incorrect_answers: [3][]const u8,
};

/// Makes obtaining new Trivias convenient.
pub fn TriviaProvider(buffer_size: comptime_int) type {
    if (buffer_size < 1 or 50 < buffer_size) {
        @compileError("buffer_size should be between 1 and 50");
    }

    return struct {
        current: usize,
        trivias: [buffer_size]Trivia,
        allocator: Allocator,

        /// Initializes a new TriviaProvider.
        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .current = buffer_size,
                .trivias = std.mem.zeroes([buffer_size]Trivia),
                .allocator = allocator,
            };
        }

        /// Obtains a new trivia.
        pub fn next(self: *@This()) !Trivia {
            if (buffer_size <= self.current) {
                // Get new trivias whenever we run out.
                try self.newTrivias();
                self.current = 0;
            }

            defer self.current += 1;
            return self.trivias[self.current];
        }

        /// Fills the trivias array with new HISTORY trivias obtained from the trivia database.
        fn newTrivias(self: *@This()) !void {
            // Here we get the questions, answers and some incorrect answers through an http request.
            // data is a []const u8 containing JSON as text.
            // 23 here refers to the category HISTORY.
            const data = try requestTrivias(self.allocator, buffer_size, 23);
            defer self.allocator.free(data);

            // THE MOST IMPORTANT PART: parsing the trivias
            self.trivias = try parseTrivias(buffer_size, data, self.allocator);
        }
    };
}

// This is where the evil-json magic happens.
fn parseTrivias(amount: comptime_int, data: []const u8, allocator: Allocator) ![amount]Trivia {

    // This parses the data into a Parsed struct
    const parsed = try json.parse(data, allocator);
    // After obtaining all the necessary data we will free the parsed JSON.
    defer parsed.deinit();

    var result: [amount]Trivia = std.mem.zeroes([amount]Trivia);

    for (0..amount) |i| {
        // We create a json.Access from the parsed data, it uses the same allocator that parsed was allocated with.
        // accessUnmanaged() is also available if we want a custom allocator.
        // Or we could also use Access.init(...) passing both the value and allocator.
        var a = parsed.access();

        // We want to drop this access after the end of the scope.
        // This is necessary because we won't use get_and_deinit() on this access.
        defer a.deinit();

        // We progress the access by selecting the value with key "results" and then selecting the
        // item at index i. Open Trivia DB returns multiple questions
        // (we can specify how many in the request)
        _ = a.o("results").a(i);

        // We clone the access here which allows us to keep our "progress" in a, while progressing
        // further on a1 to get the value at the "question" key.
        //
        // There are two methods get() and get_and_deinit() that one can use to evaluate an
        // access (obtain the actual JSON value).
        var a1 = try a.clone();
        const question = try allocator.dupe(u8, (try a1.o("question").get_and_deinit()).string);

        // Notice we also dupe the memory because we will free the parsed JSON,
        // as it contains more information than what we need.

        // Again we clone a and progress down the JSON object to get the value at the "correct answer" key.
        var a2 = try a.clone();
        const correct_answer = try allocator.dupe(u8, (try a2.o("correct_answer").get_and_deinit()).string);

        // We get the values at "incorrect answers" similarily as the other two above, "array" here is an std.ArrayList(Value).
        var a3 = try a.clone();
        const incorrect_answers_array = (try a3.o("incorrect_answers").get_and_deinit()).array;

        var incorrect_answers: [3][]const u8 = std.mem.zeroes([3][]const u8);
        for (incorrect_answers_array.items, 0..) |answer, j| {
            incorrect_answers[j] = try allocator.dupe(u8, answer.string);
        }

        result[i] = Trivia{
            .question = question,
            .correct_answer = correct_answer,
            .incorrect_answers = incorrect_answers,
        };
    }

    return result;
}

// Requests trivias from the Open Trivia Database, the response is a slice containing JSON data.
fn requestTrivias(
    allocator: Allocator,
    amount: u8,
    category: u8,
) ![]const u8 {
    const amount_val = try std.fmt.allocPrint(allocator, "{d}", .{amount});
    const category_val = try std.fmt.allocPrint(allocator, "{d}", .{category});

    const host = "https://opentdb.com/api.php";
    const params: [3][]const u8 = .{ "amount", "category", "type" };
    const values: [3][]const u8 = .{ amount_val, category_val, "multiple" };

    var url = std.ArrayList(u8).init(allocator);
    defer url.deinit();

    try url.appendSlice(host);
    try url.append('?');
    for (params, values) |param, value| {
        try url.appendSlice(param);
        try url.append('=');
        try url.appendSlice(value);
        try url.append('&');
    }

    allocator.free(amount_val);
    allocator.free(category_val);

    const uri = Uri.parse(url.items) catch unreachable;

    var client = Client{ .allocator = allocator };

    var request = try client.open(http.Method.GET, uri, .{
        .server_header_buffer = try allocator.alloc(u8, 500),
    });
    try request.send(.{});
    try request.wait();

    return try request.reader().readAllAlloc(allocator, 10240);
}
