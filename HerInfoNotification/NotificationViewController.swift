//
//  NotificationViewController.swift
//  通知内容扩展的主类
//
//  【它在整条链里的位置】
//  主 App（ReminderService）排一条通知 → 系统在锁屏上渲染
//    · 收起态：用的还是系统那套（标题 + 正文），与画布 14 屏逐字一致
//    · 长按展开：系统把控制权交给这个扩展，画布 36 屏的样子从这里出来
//  用户点「开心」→ 丢进共享收件箱 → 主 App 下次启动/回前台时落成一条 Mood
//
//  【这个类只做三件事】
//  ① 接住系统给的通知，把 userInfo 读成 Payload
//  ② 按高度判断「现在是收起还是展开」，决定画不画
//  ③ 把打标丢进收件箱
//  它**不碰数据库、不碰网络** —— 理由见 NotificationContract.swift。
//

import UIKit
import SwiftUI
import UserNotifications
// 注意：UNNotificationContentExtension 与 UNNotificationContentExtensionResponseOption
// 这两个类型属于 **UserNotificationsUI**，不是 UserNotifications。
// 只 import UserNotifications 的报错是「cannot find type … in scope」——
// 容易误以为是 iOS 版本或 target 配错，其实只差这一行。
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    /// 展开 / 收起的判定阈值。
    ///
    /// **iOS 没有提供「通知是否已展开」的查询接口** —— 只能在布局回调里看高度，
    /// 所以这是一个启发式判断，不是系统承诺的行为：
    ///   收起 ≈ 0（我们把内容视图压成 0 高，见 Info.plist 的 ratio = 0.12）
    ///   展开 ≈ 500 以上
    /// 120 落在两不管的地带。真机上如果出现「长按展开了但内容没长出来」，
    /// 第一件事是把这个数调小，而不是去改视图。
    private static let expandedThreshold: CGFloat = 120

    private var host: UIHostingController<NotificationContentView>?
    private var payload = HINotify.Payload.empty
    private var image: UIImage?
    private var isExpanded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // 透明底：系统已经铺了毛玻璃，再填一层会把壁纸的模糊感盖掉。
        view.backgroundColor = .clear
        rebuild()
    }

    // MARK: - 系统回调

    func didReceive(_ notification: UNNotification) {
        let c = notification.request.content
        payload = HINotify.Payload(userInfo: c.userInfo,
                                   fallbackTitle: c.title,
                                   fallbackBody: c.body)
        image = Self.loadImage(from: c)
        rebuild()
    }

    /// 分类动作（「打标…」「1 小时后」「今天不用了」）也会送一份给扩展 ——
    /// 因为扩展可能正显示着。
    ///
    /// 这里**一律原样转发给主 App**：写库、重排提醒只应该有一个地方做。
    /// 两个进程各处理一半，就是两份真相的开始。
    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        completion(.dismissAndForwardAction)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let nowExpanded = view.bounds.height >= Self.expandedThreshold
        guard nowExpanded != isExpanded else { return }
        isExpanded = nowExpanded
        rebuild()
    }

    // MARK: - 内部

    private func rebuild() {
        let content = NotificationContentView(
            payload: payload,
            image: image,
            expanded: isExpanded,
            onMark: { [weak self] mood in self?.mark(mood) }
        )

        if let host {
            host.rootView = content
            host.view.invalidateIntrinsicContentSize()
            return
        }

        let h = UIHostingController(rootView: content)
        h.view.backgroundColor = .clear
        addChild(h)
        view.addSubview(h.view)
        h.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            h.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            h.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            h.view.topAnchor.constraint(equalTo: view.topAnchor),
            h.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        h.didMove(toParent: self)
        host = h
    }

    /// 打标：丢进共享收件箱，然后收起通知。
    private func mark(_ mood: HINotify.Mood) {
        HINotify.Inbox.push(.init(recordID: payload.recordID,
                                  level: mood.rawValue,
                                  at: .now))

        // 给「已记下」留一点可见时间。立刻把通知收走，等于没有反馈 ——
        // 而锁屏上的按钮最怕的就是「点了之后不知道成没成」。
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            extensionContext?.dismissNotification()
        }
    }

    /// 读配图。
    ///
    /// 主 App 用 `UNNotificationAttachment` 把照片交给系统，系统会把它拷进
    /// 这条通知自己的目录 —— 所以这里直接读 `attachments.first.url` 就够了。
    /// **不需要共享容器**，也读不到（更不该读）主 App 的沙盒。
    private static func loadImage(from content: UNNotificationContent) -> UIImage? {
        guard let url = content.attachments.first?.url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
