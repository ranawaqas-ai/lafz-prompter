import Combine
import CoreVideo
import Dependencies
import Foundation

/// The display's refresh ticks that move the script while it plays, as
/// timestamps on the main queue.
struct FrameClock: Sendable {
    var ticks: @Sendable () -> AnyPublisher<CFTimeInterval, Never>
}

extension FrameClock: DependencyKey {
    static let liveValue = FrameClock(ticks: { CADisplayLinkPublisher().eraseToAnyPublisher() })
    /// No ticks: tests drive playback by calling `tick(current:)` themselves.
    static let stopped = FrameClock(ticks: { Empty().eraseToAnyPublisher() })
}

extension DependencyValues {
    var frameClock: FrameClock {
        get { self[FrameClock.self] }
        set { self[FrameClock.self] = newValue }
    }
}

private final class CADisplayLinkProxy {
    let subject = PassthroughSubject<CFTimeInterval, Never>()
    var link: CVDisplayLink?
    
    init() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        self.link = link
        if let l = link {
            CVDisplayLinkSetOutputCallback(l, { (_, _, _, _, _, userInfo) -> CVReturn in
                let ref = Unmanaged<CADisplayLinkProxy>.fromOpaque(userInfo!).takeUnretainedValue()
                let ts = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async {
                    ref.subject.send(ts)
                }
                return kCVReturnSuccess
            }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            CVDisplayLinkStart(l)
        }
    }
    
    deinit {
        if let l = link {
            CVDisplayLinkStop(l)
        }
    }
}

struct CADisplayLinkPublisher: Publisher {
    typealias Output = CFTimeInterval
    typealias Failure = Never
    
    func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, CFTimeInterval == S.Input {
        let proxy = CADisplayLinkProxy()
        subscriber.receive(subscription: SubscriptionImpl(subscriber: subscriber, proxy: proxy))
    }
    
    private final class SubscriptionImpl<S: Subscriber>: Subscription where S.Input == CFTimeInterval, S.Failure == Never {
        private var subscriber: S?
        private var proxy: CADisplayLinkProxy?
        private var cancellables: Set<AnyCancellable> = []
        
        init(subscriber: S, proxy: CADisplayLinkProxy) {
            self.subscriber = subscriber
            self.proxy = proxy
            
            proxy.subject
                .sink { [weak self] value in
                    _ = self?.subscriber?.receive(value)
                }
                .store(in: &cancellables)
        }
        
        func request(_ demand: Subscribers.Demand) {
            // demand not used
        }
        
        func cancel() {
            subscriber = nil
            proxy = nil
            cancellables.removeAll()
        }
    }
}
