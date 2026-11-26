import Foundation

public enum WindowResolver {
    public static let windowRole = "AXWindow"
    public static let maxParentDepth = 8

    /// Returns the element to treat as the hovered window.
    /// 1. If window(hit) returns an element whose role(…) == windowRole, return it.
    /// 2. Otherwise walk from hit: if role(e) == windowRole return e; else e = parent(e); stop after maxParentDepth
    ///    parent steps or when parent returns nil, and return the element reached (the pre-L4 behaviour).
    public static func resolve<E>(
        hit: E,
        window: (E) -> E?,
        role: (E) -> String?,
        parent: (E) -> E?
    ) -> E {
        if let candidate = window(hit), role(candidate) == windowRole {
            return candidate
        }
        var element = hit
        for _ in 0..<maxParentDepth {
            if role(element) == windowRole {
                return element
            }
            guard let next = parent(element) else {
                return element
            }
            element = next
        }
        return element
    }
}
