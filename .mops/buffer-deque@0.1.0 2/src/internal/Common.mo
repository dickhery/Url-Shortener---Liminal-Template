module {
    // The following constants are used to manage the capacity.
    // The length of `elements` is increased by `INCREASE_FACTOR` when capacity is reached.
    // The length of `elements` is decreased by `DECREASE_FACTOR` when capacity is strictly less than
    // `DECREASE_THRESHOLD`.

    // INCREASE_FACTOR = INCREASE_FACTOR_NUME / INCREASE_FACTOR_DENOM (with floating point division)
    // Keep INCREASE_FACTOR low to minimize cycle limit problem
    public let INCREASE_FACTOR_NUME = 3;
    public let INCREASE_FACTOR_DENOM = 2;
    public let DECREASE_THRESHOLD = 4; // Don't decrease capacity too early to avoid thrashing
    public let DECREASE_FACTOR = 2;
    public let DEFAULT_CAPACITY = 8;

    /// > Adapted from the base implementation of the `Buffer` class
    public func newCapacity(oldCapacity : Nat) : Nat {
        if (oldCapacity == 0) {
            1;
        } else {
            // calculates ceil(oldCapacity * INCREASE_FACTOR) without floats
            ((oldCapacity * INCREASE_FACTOR_NUME) + INCREASE_FACTOR_DENOM - 1) / INCREASE_FACTOR_DENOM;
        };
    };

    public type BufferInterface<A> = {
        get: Nat -> A;
        size: () -> Nat;
    };
}