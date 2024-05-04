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

    while (true) {
        if (getNextTrivia(allocator)) |trivia| {
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

                const index: ?usize = std.fmt.parseInt(usize, input.?[0 .. input.?.len - 1], 10) catch null;
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

// This is where the evil-json magic happens
fn getNextTrivia(allocator: Allocator) !Trivia {
    // Here we get the question, answer and some incorrect answers through an http request
    // data is a []const u8 containing JSON as text
    const data = try requestHistoryQuestion(allocator);

    // This parses the data into a Parsed struct.
    const parsed = try json.parse(data, allocator);

    // We create an Access from the parsed data, it uses the same allocator that parsed was allocated with
    // accessUnmanaged() is also available if we want a custom allocator
    // or using Access.init(...) passing both the value and allocator is also an option
    var a = parsed.access();
    defer a.deinit();

    // We progress the access selecting the value with key "result" in the data
    // and then selecting the first thing. Open Trivia DB can return multiple questions,
    // but we only request one in this example.
    _ = a.o("results").a(0);

    // We clone the access here which allows us to keep our "progress" in a, while progressing further
    // on a1 to get the question.
    //
    // There are two methods get() and get_and_deinit() which one can use to evaluate an
    // access (obtain the actual json value)
    var a1 = try a.clone();
    const question = (try a1.o("question").get_and_deinit()).string;

    // Again we clone a and progress further down the json object to get the correct answer.
    var a2 = try a.clone();
    const correct_answer = (try a2.o("correct_answer").get_and_deinit()).string;

    // We get the incorrect answers similarily as above, array here is an std.ArrayList(Value)
    var a3 = try a.clone();
    const incorrect_answers_array = (try a3.o("incorrect_answers").get_and_deinit()).array;

    var incorrect_answers: [3][]const u8 = std.mem.zeroes([3][]const u8);
    for (incorrect_answers_array.items, 0..) |answer, i| {
        incorrect_answers[i] = answer.string;
    }

    return Trivia{
        .question = question,
        .correct_answer = correct_answer,
        .incorrect_answers = incorrect_answers,
    };
}

/// Requests a history question from the Open Trivia Database.
fn requestHistoryQuestion(allocator: Allocator) ![]const u8 {
    var client = Client{ .allocator = allocator };

    const url = "https://opentdb.com/api.php?amount=1&category=23&type=multiple";
    const uri = try Uri.parse(url);

    var request = try client.open(http.Method.GET, uri, .{
        .server_header_buffer = try allocator.alloc(u8, 500),
    });

    try request.send(.{});
    try request.wait();

    return try request.reader().readAllAlloc(allocator, 1024);
}
