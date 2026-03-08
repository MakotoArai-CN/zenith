pub const Sampler = struct {
    samples: [MAX_SAMPLES]f64 = undefined,
    count: usize = 0,

    const MAX_SAMPLES = 1024;

    pub fn add(self: *Sampler, v: f64) void {
        if (self.count < MAX_SAMPLES) {
            self.samples[self.count] = v;
            self.count += 1;
        }
    }

    pub fn median(self: *Sampler) f64 {
        if (self.count == 0) return 0;
        if (self.count == 1) return self.samples[0];

        // Insertion sort (samples are small, max 1024)
        var slice = self.samples[0..self.count];
        for (1..slice.len) |i| {
            const key = slice[i];
            var j: usize = i;
            while (j > 0 and slice[j - 1] > key) {
                slice[j] = slice[j - 1];
                j -= 1;
            }
            slice[j] = key;
        }

        if (self.count % 2 == 1) {
            return slice[self.count / 2];
        } else {
            return (slice[self.count / 2 - 1] + slice[self.count / 2]) / 2.0;
        }
    }
};
