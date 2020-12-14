pub const Chip = struct {
    output: f64,
    const Self = @This();

    pub fn init(clock: u32, sample_rate: u32) Self {
        return Self{ .output = 0.0 };
    }
    pub fn writeRegister(s: *Self, offset: i32, data: i32) void {}
    pub fn process(s: *Self) void {}
};
