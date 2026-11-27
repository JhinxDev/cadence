import CarPlay
import Foundation
import UIKit
import CadenceCore

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let homeTab = CPListTemplate(title: "Mixes", sections: [
            CPListSection(items: [
                CPListItem(text: "My Supermix", detailText: "Heavy rotation & fresh finds"),
                CPListItem(text: "Discover Mix", detailText: "New tracks tailored to your taste"),
                CPListItem(text: "Replay Mix", detailText: "On repeat"),
            ]),
        ])
        homeTab.tabImage = UIImage(systemName: "sparkles")

        let tabBar = CPTabBarTemplate(templates: [homeTab])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }
}
