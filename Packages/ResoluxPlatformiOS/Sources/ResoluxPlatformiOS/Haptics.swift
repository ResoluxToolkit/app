import UIKit

public struct Haptics: Sendable {
  public init() {}
  
  public func impact() {
    UIImpactFeedbackGenerator().impactOccurred()
  }
  
  public func notification(_ event: UINotificationFeedbackGenerator.FeedbackType = .success) {
  UINotificationFeedbackGenerator().notificationOccurred(event)
  }
}
