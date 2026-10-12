import Flutter
import UIKit

public class InterceptlySharePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.stormx.interceptly/share",
      binaryMessenger: registrar.messenger()
    )
    let instance = InterceptlySharePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "shareFile" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String, !path.isEmpty else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing file path", details: nil))
      return
    }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(FlutterError(code: "FILE_NOT_FOUND", message: "File does not exist", details: path))
      return
    }
    DispatchQueue.main.async {
      guard let root = self.topViewController() else {
        result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No presenting view controller", details: nil))
        return
      }
      var items: [Any] = [url]
      if let text = args["text"] as? String, !text.isEmpty {
        items.append(text)
      }
      let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
      if let subject = args["subject"] as? String, !subject.isEmpty {
        activity.setValue(subject, forKey: "subject")
      }
      if let popover = activity.popoverPresentationController {
        let originX = (args["originX"] as? Double) ?? Double(root.view.bounds.midX)
        let originY = (args["originY"] as? Double) ?? Double(root.view.bounds.midY)
        let originW = (args["originWidth"] as? Double) ?? 1
        let originH = (args["originHeight"] as? Double) ?? 1
        popover.sourceView = root.view
        popover.sourceRect = CGRect(x: originX, y: originY, width: originW, height: originH)
        popover.permittedArrowDirections = .any
      }
      root.present(activity, animated: true)
      result(true)
    }
  }

  private func topViewController(
    _ base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
  ) -> UIViewController? {
    if let nav = base as? UINavigationController {
      return topViewController(nav.visibleViewController)
    }
    if let tab = base as? UITabBarController {
      return topViewController(tab.selectedViewController)
    }
    if let presented = base?.presentedViewController {
      return topViewController(presented)
    }
    return base
  }
}
