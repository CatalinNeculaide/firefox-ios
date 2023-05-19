// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import Shared
import Common

class UpdateViewController: UIViewController,
                            OnboardingViewControllerProtocol,
                            Themeable {
    struct UX {
        static let closeButtonTopPadding: CGFloat = 32
        static let closeButtonRightPadding: CGFloat = 16
        static let closeButtonSize: CGFloat = 30
        static let pageControlHeight: CGFloat = 40
    }

    // MARK: - Properties
    var viewModel: OnboardingViewModelProtocol
    var didFinishFlow: (() -> Void)?
    var notificationCenter: NotificationProtocol
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?

    private lazy var closeButton: UIButton = .build { button in
        button.setImage(UIImage(named: ImageIdentifiers.bottomSheetClose), for: .normal)
        button.addTarget(self, action: #selector(self.closeUpdate), for: .touchUpInside)
        button.accessibilityIdentifier = AccessibilityIdentifiers.Upgrade.closeButton
    }

    lazy var pageController: UIPageViewController = {
        let pageVC = UIPageViewController(transitionStyle: .scroll,
                                          navigationOrientation: .horizontal)
        pageVC.dataSource = self
        pageVC.delegate = self

        return pageVC
    }()

    lazy var pageControl: UIPageControl = .build { pageControl in
        pageControl.currentPage = 0
        pageControl.numberOfPages = self.viewModel.availableCards.count
        pageControl.isUserInteractionEnabled = false
        pageControl.accessibilityIdentifier = AccessibilityIdentifiers.Upgrade.pageControl
    }

    // MARK: - Initializers
    init(
        viewModel: UpdateViewModel,
        themeManager: ThemeManager = AppContainer.shared.resolve(),
        notificationCenter: NotificationProtocol = NotificationCenter.default
    ) {
        self.viewModel = viewModel
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter
        super.init(nibName: nil, bundle: nil)

        self.viewModel.setupViewControllerDelegates(with: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        applyTheme()
        listenForThemeChange(view)
    }

    // MARK: View setup
    private func setupView() {
        guard let viewModel = viewModel as? UpdateViewModel else { return }

        if viewModel.shouldShowSingleCard {
            setupSingleInfoCard()
        } else {
            setupMultipleCards()
            setupMultipleCardsConstraints()
        }

        if viewModel.isDismissable { setupCloseButton() }
    }

    private func setupSingleInfoCard() {
        guard let cardViewController = viewModel.availableCards.first else { return }

        addChild(cardViewController)
        view.addSubview(cardViewController.view)
        cardViewController.didMove(toParent: self)
    }

    private func setupMultipleCards() {
        if let firstViewController = viewModel.availableCards.first {
            pageController.setViewControllers([firstViewController],
                                              direction: .forward,
                                              animated: true,
                                              completion: nil)
        }
    }

    private func setupMultipleCardsConstraints() {
        addChild(pageController)
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        view.addSubview(pageControl)

        NSLayoutConstraint.activate([
            pageControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            pageControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupCloseButton() {
        guard viewModel.isDismissable else { return }
        view.addSubview(closeButton)
        view.bringSubviewToFront(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.topAnchor,
                                             constant: UX.closeButtonTopPadding),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                  constant: -UX.closeButtonRightPadding),
            closeButton.widthAnchor.constraint(equalToConstant: UX.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: UX.closeButtonSize)
        ])
    }

    // Button Actions
    @objc
    private func closeUpdate() {
        didFinishFlow?()
// FXIOS-6358 - Implement telemetry
//        viewModel.sendCloseButtonTelemetry(index: pageControl.currentPage)
    }

    @objc
    func dismissSignInViewController() {
        dismiss(animated: true, completion: nil)
        closeUpdate()
    }

    @objc
    func dismissPrivacyPolicyViewController() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Theme
    func applyTheme() {
        let theme = themeManager.currentTheme
        view.backgroundColor = theme.colors.layer2

        viewModel.availableCards.forEach { $0.applyTheme() }

        guard let viewModel = viewModel as? UpdateViewModel,
              !viewModel.shouldShowSingleCard
        else { return }
        pageControl.currentPageIndicatorTintColor = theme.colors.actionPrimary
        pageControl.pageIndicatorTintColor = theme.colors.actionSecondary
    }
}

// MARK: UIPageViewControllerDataSource & UIPageViewControllerDelegate
extension UpdateViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let onboardingVC = viewController as? OnboardingCardViewController,
              let index = getCardIndex(viewController: onboardingVC)
        else { return nil }

        pageControl.currentPage = index
        return getNextOnboardingCard(index: index, goForward: false)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let onboardingVC = viewController as? OnboardingCardViewController,
              let index = getCardIndex(viewController: onboardingVC)
        else { return nil }

        pageControl.currentPage = index
        return getNextOnboardingCard(index: index, goForward: true)
    }
}

extension UpdateViewController: OnboardingCardDelegate {
    func handleButtonPress(
        for action: OnboardingActions,
        from cardName: String
    ) {
        switch action {
        case .nextCard:
            showNextPage(from: cardName) {
                self.didFinishFlow?()
            }
        case .syncSignIn:
            let fxaParams = FxALaunchParams(entrypoint: .updateOnboarding, query: [:])
            presentSignToSync(
                with: fxaParams,
                selector: #selector(dismissSignInViewController)
            ) {
                self.closeUpdate()
            }
        case .readPrivacyPolicy:
            presentPrivacyPolicy(
                from: cardName,
                selector: #selector(dismissPrivacyPolicyViewController))
        case .openDefaultBrowserPopup:
            presentDefaultBrowserPopup(from: cardName)
        default:
            break
        }
    }
}

// MARK: UIViewController setup
extension UpdateViewController {
    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var shouldAutorotate: Bool {
        return false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // This actually does the right thing on iPad where the modally
        // presented version happily rotates with the iPad orientation.
        return .portrait
    }
}
