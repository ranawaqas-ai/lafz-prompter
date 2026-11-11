import Dependencies

/// The SQLite file of past Call Assist answers.
private enum AnswerHistoryKey: DependencyKey {
    static let liveValue = AnswerHistoryStore()
}

extension DependencyValues {
    var answerHistory: AnswerHistoryStore {
        get { self[AnswerHistoryKey.self] }
        set { self[AnswerHistoryKey.self] = newValue }
    }
}
