import Foundation
#if SWIFT_PACKAGE
@testable import FollowScriptCore
#else
@testable import FollowScript
#endif

enum AlignmentFixtures {
    static let presentation = """
    Good morning, and thank you for joining us. Today I want to share what we learned while designing calmer digital tools. We began by watching people work under pressure and listening carefully to the language they used. The research demonstrated that interruptions remain a significant challenge for focused creative work.

    We first examined attention. We then examined participant comfort. Finally, we considered confidence and control. The strongest designs did not demand constant attention; they stayed quiet, offered clear choices, and recovered gracefully when plans changed.

    Our next step is to test these ideas with a broader community. We will measure comprehension, response time, and long-term trust. Most importantly, we will keep listening. Thank you for your time, and I look forward to the conversation.
    """

    static let sequentialRecognition = [
        "good morning and thank you for joining us",
        "today I want to share what we learned while designing calmer digital tools",
        "we began by watching people work under pressure and listening carefully",
        "the research demonstrated interruptions remain a significant challenge",
        "we first examined attention",
        "we then examined participant comfort",
        "finally we considered confidence and control",
        "the strongest designs did not demand constant attention they stayed quiet",
        "our next step is to test these ideas with a broader community",
        "we will measure comprehension response time and long term trust",
        "most importantly we will keep listening thank you for your time"
    ]
}
