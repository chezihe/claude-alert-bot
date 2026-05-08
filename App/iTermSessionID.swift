// App/iTermSessionID.swift — Phase 3 D3-01 UUID 정규화 추출자 + T-INJECTION-01 whitelist validator.
// Rule: "wXtYpZ:UUID-XXXX" envelope → "UUID-XXXX". ":" 미포함 입력은 그대로 반환 (legacy 안전망).
// PATTERNS.md §iTermSessionID: ProjectName과 동일한 enum-of-static-funcs Foundation-only.
//
// D3-02 의미 잠금: AppleScript `id of session` = UUID-only. SessionRecord.itermSessionID
// 는 정규화된 UUID-only 형식으로 저장되며 frontmostMatches / jump-by-uuid 비교는
// UUID-only 끼리 직접 비교 (== 연산).
//
// T-INJECTION-01: isValid(_:) is the gate for AppleScript source substitution
// in plan 03-04. UUID character domain = [A-Fa-f0-9-] in 8-4-4-4-12 form;
// Foundation's UUID parser is the source of truth — anything it rejects, we reject.
import Foundation

enum iTermSessionID {
    /// D3-01: Reporter envelope `iterm_session_id` is shaped `wXtYpZ:UUID`.
    /// iTerm2 AppleScript `id of session` is UUID-only — Swift-side strips before comparison.
    /// Returns nil for nil/empty input (so call sites can flow `?.let`).
    /// Idempotent: passing an already-stripped UUID returns it unchanged.
    static func uuid(fromRaw raw: String?) -> String? {
        guard let s = raw, !s.isEmpty else { return nil }
        guard let colon = s.firstIndex(of: ":") else {
            // No colon → assume already-stripped UUID, return as-is (legacy safety).
            return s
        }
        let after = s[s.index(after: colon)...]
        return after.isEmpty ? nil : String(after)
    }

    /// T-INJECTION-01 — whitelist validator for AppleScript source substitution.
    /// Strict: 36 chars, only [A-Fa-f0-9-], standard 8-4-4-4-12 dash positions.
    /// Foundation `UUID(uuidString:)` is the source of truth — rejects anything
    /// the OS doesn't accept as a UUID. The whitelist guarantees that the
    /// `String(format: jumpScriptTemplate, uuid)` substitution in plan 03-04
    /// cannot inject AppleScript code.
    static func isValid(_ candidate: String) -> Bool {
        return UUID(uuidString: candidate) != nil
    }
}
