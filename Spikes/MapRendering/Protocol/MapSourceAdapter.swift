/// A synchronous, pure normalization seam; callers own acquisition and resource lifetimes.
protocol MapSourceAdapter {
    associatedtype Input

    func adapt(_ input: Input) throws -> MapSource
}
