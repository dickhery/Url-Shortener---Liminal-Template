import Order "mo:base/Order";
import Result "mo:base/Result";

module {
    type Order = Order.Order;
    type Result<T, E> = Result.Result<T, E>;

    public type CmpFn<A> = (A, A) -> Int8;
    public type MultiCmpFn<A, B> = (A, B) -> Int8;

}