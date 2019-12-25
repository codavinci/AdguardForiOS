/**
      This file is part of Adguard for iOS (https://github.com/AdguardTeam/AdguardForiOS).
      Copyright © Adguard Software Limited. All rights reserved.

      Adguard for iOS is free software: you can redistribute it and/or modify
      it under the terms of the GNU General Public License as published by
      the Free Software Foundation, either version 3 of the License, or
      (at your option) any later version.

      Adguard for iOS is distributed in the hope that it will be useful,
      but WITHOUT ANY WARRANTY; without even the implied warranty of
      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
      GNU General Public License for more details.

      You should have received a copy of the GNU General Public License
      along with Adguard for iOS.  If not, see <http://www.gnu.org/licenses/>.
*/

import UIKit

class MainPageController: UIViewController, UIViewControllerTransitioningDelegate, DateTypeChangedProtocol, ChartPointsChangedDelegate, VpnServiceNotifierDelegate, ComplexProtectionDelegate, ComplexSwitchDelegate, OnboardingControllerDelegate {
    
    var ready = false
    var onReady: (()->Void)? {
        didSet {
            if ready && onReady != nil {
                callOnready()
            }
        }
    }
    
    // MARK: - Nav bar elements
    
    @IBOutlet weak var updateButton: UIBarButtonItem! {
        didSet{
            let icon = UIImage(named: "refresh-icon")
            let iconSize = CGRect(origin: .zero, size: CGSize(width: 24.0, height: 24.0))
            let tintColor = UIColor(hexString: "#67b279")
            iconButton = UIButton(frame: iconSize)
            iconButton?.setBackgroundImage(icon, for: .normal)
            iconButton?.tintColor = tintColor
            updateButton.customView = iconButton
            iconButton?.addTarget(self, action: #selector(updateFilters(_:)), for: .touchUpInside)
        }
    }

    // MARK: - Protection status elements
    
    @IBOutlet weak var safariProtectionButton: RoundRectButton!
    @IBOutlet weak var systemProtectionButton: RoundRectButton!
    
    @IBOutlet weak var protectionStateLabel: ThemableLabel!
    @IBOutlet weak var protectionStatusLabel: ThemableLabel!
    
    
    // MARK: - Complex protection switch
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var complexProtectionView: UIView!
    @IBOutlet weak var complexProtectionSwitch: ComplexProtectionSwitch!
    
    
    // MARK: - Statistics elements
    
    @IBOutlet weak var changeStatisticsDatesButton: UIButton!
    @IBOutlet weak var chartView: ChartView!
    
    
    @IBOutlet weak var statisticsStackView: UIStackView!
    
    @IBOutlet weak var requestsButton: UIButton!
    @IBOutlet weak var blockedButton: UIButton!
    
    @IBOutlet weak var requestsNumberLabel: ThemableLabel!
    @IBOutlet weak var blockedNumberLabel: ThemableLabel!
    
    @IBOutlet weak var requestsTextLabel: ThemableLabel!
    @IBOutlet weak var blockedTextLabel: ThemableLabel!
    
    
    // MARK: Get Pro elements
    
    @IBOutlet weak var getProView: UIView!
    @IBOutlet weak var adguardManImageView: UIImageView!
    @IBOutlet weak var manDialogView: UIView!
    @IBOutlet weak var manDialogText: ThemableLabel!
    @IBOutlet weak var getProButton: UIButton!
    
    
    // MARK: - Content blockers view
    
    @IBOutlet weak var contentBlockerViewIphone: UIView!
    @IBOutlet weak var contentBlockerViewIpad: UIView!

    
    // MARK: - Themable labels
    
    @IBOutlet var themableLabels: [ThemableLabel]!
    
    
    // MARK: - Constraints
    @IBOutlet weak var contentBlockerViewConstraint: NSLayoutConstraint!
    
    
    // MARK: - Variables
    
    private var iconButton: UIButton? = nil
    private var complexText = ""
    private let getProSegueId = "getProSegue"
    private let showOnboardingSegueId = "showOnboardingSegue"
    private let videoTutorialSegueId = "videoTutorialSegue"
    
    private var proStatus: Bool {
        return configuration.proStatus
    }
    private var contentBlockersGestureRecognizer: UIPanGestureRecognizer? = nil
    
    
    // MARK: - Services
    
    private lazy var configuration: ConfigurationService = { ServiceLocator.shared.getService()! }()
    private lazy var antibanner: AESAntibannerProtocol = { ServiceLocator.shared.getService()! }()
    private lazy var theme: ThemeServiceProtocol = { ServiceLocator.shared.getService()! }()
    private lazy var resources: AESharedResourcesProtocol = { ServiceLocator.shared.getService()! }()
    private lazy var complexProtection: ComplexProtectionServiceProtocol = { ServiceLocator.shared.getService()! }()
    private lazy var vpnService: VpnServiceProtocol = { ServiceLocator.shared.getService()! }()
    
    
    // MARK: - View models
    
    private var chartModel: ChartViewModelProtocol = ChartViewModel(ServiceLocator.shared.getService()!)
    private var mainPageModel: MainPageModelProtocol?
    
    
    // MARK: - Observers
    
    private var themeNotificationToken: NotificationToken?
    private var appWillEnterForeground: NotificationToken?
    private var observations: [NSKeyValueObservation] = []
    
    
    // MARK: - View Controller life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mainPageModel = MainPageModel(antibanner: antibanner)
        
        addObservers()
        chooseRequest()
        changeProtectionStatusLabel()
        observeContentBlockersState()
    
        chartModel.chartPointsChangedDelegate = self
        complexProtectionSwitch.delegate = self
        
        contentBlockersGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleContentBlockersView(_:)))
        if let recognizer = contentBlockersGestureRecognizer {
            contentBlockerViewIpad.addGestureRecognizer(recognizer)
        }
        
        if !(resources.sharedDefaults().bool(forKey: OnboardingShowed)) {
            showOnboarding()
            resources.sharedDefaults().set(true, forKey: OnboardingShowed)
        }
        else {
            ready = true
            callOnready()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        vpnService.notifier = self
        complexProtection.delegate = self
        updateTheme()
        observeProStatus()
        chartModel.obtainStatistics()
        updateTextForButtons()
        checkProtectionStates()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let nav = navigationController as? MainNavigationController {
            nav.addGestureRecognizer()
        }
    }
        
    deinit {
        removeObservers()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return theme.statusbarStyle()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == showOnboardingSegueId {
            if let controller = segue.destination as? OnboardingController {
                controller.delegate = self
            }
        }
        if segue.identifier == videoTutorialSegueId {
            if let controller = segue.destination as? AEUIPlayerViewController {
                controller.completionBlock = { [weak self] in
                    guard let self = self else { return }
                    self.performSegue(withIdentifier: self.showOnboardingSegueId, sender: self)
                }
            }
        }
    }
    
    // MARK: - Actions

    
    // MARK: - Nav Bar Actions
    
    @objc private func updateFilters(_ sender: Any) {
        mainPageModel?.updateFilters(start: {
            DispatchQueue.main.async { [weak self] in
                self?.updateStarted()
                self?.protectionStatusLabel.text = ACLocalizedString("update_filter_start_message", nil)
            }
        }, finish: { [weak self] (message) in
            DispatchQueue.main.async {
                self?.protectionStatusLabel.text = message
                self?.updateEnded()
            }
        }, error: { [weak self] (message) in
            DispatchQueue.main.async {
                self?.protectionStatusLabel.text = message
                self?.updateEnded()
            }
        })
    }
    
    // MARK: - Protection Status Actions
    
    @IBAction func changeSafariProtectionState(_ sender: RoundRectButton) {
        safariProtectionButton.buttonIsOn = !safariProtectionButton.buttonIsOn
        complexProtection.switchSafariProtection(state: safariProtectionButton.buttonIsOn)
        activityIndicator.startAnimating()
    }
    
    @IBAction func changeSystemProtectionState(_ sender: RoundRectButton) {
        systemProtectionButton.buttonIsOn = !systemProtectionButton.buttonIsOn
        complexProtection.switchSystemProtection(state: systemProtectionButton.buttonIsOn, for: self)
        activityIndicator.startAnimating()
    }
    
    
    // MARK: - Complex protection switch action
    
    @IBAction func complexProtectionState(_ sender: ComplexProtectionSwitch) {
        let enabled = sender.isOn
        complexProtection.switchComplexProtection(state: enabled, for: self)
        activityIndicator.startAnimating()
    }
    
    
    // MARK: - Statistics Actions
    
    @IBAction func changeStatisticDates(_ sender: UIButton) {
        showChartDateTypeController()
    }
    
    @IBAction func requestsTapped(_ sender: UIButton) {
        chooseRequest()
    }
    
    @IBAction func blockedTapped(_ sender: UIButton) {
        chooseBlocked()
    }
    
    
    // MARK: - Get pro action
    
    @IBAction func getProAction(_ sender: UIButton) {
        
    }
    
    
    // MARK: - Content blockers view actions
    
    @IBAction func crossTapped(_ sender: UIButton) {
        hideContentBlockersInfo()
    }
    
    @IBAction func fixItTapped(_ sender: UIButton) {
        showOnboarding()
    }
    
    // MARK: - Observing Values from User Defaults
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        changeTextForButton(with: keyPath)
    }
    
    
    // MARK: - Vpn notifiers
       
    func tunnelModeChanged() {
        checkProtectionStates()
    }
       
    func vpnConfigurationChanged(with error: Error?) {
        if error != nil {
            ACSSystemUtils.showSimpleAlert(for: self, withTitle: nil, message: error?.localizedDescription)
            checkProtectionStates()
        }
    }
       
    func cancelledAddingVpnConfiguration() {
        checkProtectionStates()
    }
    
    
    // MARK: - Complex protection delegate method
    
    func safariProtectionChanged() {
        DispatchQueue.main.async {[weak self] in
            guard let self = self else { return }
            self.checkProtectionStates()
        }
    }
    
    func proStatusHandler() {
        performSegue(withIdentifier: getProSegueId, sender: self)
    }
    
    
    // MARK: - ChartPointsChangedDelegate method
    
    func chartPointsChanged(points: [Point]) {
        chartView.chartPoints = points
    }
    
    
    // MARK: - DateTypeChangedProtocol method
    
    func dateTypeChanged(dateType: ChartDateType) {
        changeDateTypeButton(dateType: dateType)
        chartModel.chartDateType = dateType
    }
    
    
    // MARK: - Complex switch delegate
    
    func beginTracking() {
        if let nav = navigationController as? MainNavigationController {
            nav.removeGestureRecognizer()
        }
    }
    
    
    // MARK: - Presentation delegate method
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return CustomAnimatedTransitioning()
    }
    
    // MARK: - OnboardingViewController delegate
    
    func showVideoAction(sender: UIViewController) {
        sender.dismiss(animated: true) {
            self.performSegue(withIdentifier: self.videoTutorialSegueId, sender: self)
        }
    }
    
    func onboardingDidFinish() {
        ready = true
        callOnready()
    }
    
    // MARK: - Private methods
    
    /**
     Updates theme when notification is observed
     */
    private func updateTheme(){
        navigationController?.view.backgroundColor = theme.backgroundColor
        theme.setupNavigationBar(navigationController?.navigationBar)
        
        chartView.backgroundColor = theme.backgroundColor
        view.backgroundColor = theme.backgroundColor
        theme.setupLabels(themableLabels)
        getProView.backgroundColor = theme.backgroundColor
        
        contentBlockerViewIphone.backgroundColor = theme.notificationWindowColor
        
        activityIndicator.color = theme.invertedBackgroundColor
    }
    
    /**
     Presents ChartDateTypeController
     */
    private func showChartDateTypeController(){
        guard let controller = storyboard?.instantiateViewController(withIdentifier: "ChartDateTypeController") as? ChartDateTypeController else { return }
        controller.modalPresentationStyle = .custom
        controller.transitioningDelegate = self
        controller.delegate = self
        
        present(controller, animated: true, completion: nil)
    }
    
    /**
     Set title for changeStatisticsDatesButton when it is changed
     */
    private func changeDateTypeButton(dateType: ChartDateType){
        switch dateType {
        case .day:
            changeStatisticsDatesButton.setTitle(ACLocalizedString("chart_24hours", nil), for: .normal)
        case .today:
            changeStatisticsDatesButton.setTitle(ACLocalizedString("chart_date_today", nil), for: .normal)
        case .week:
            changeStatisticsDatesButton.setTitle(ACLocalizedString("chart_7days", nil), for: .normal)
        case .month:
            changeStatisticsDatesButton.setTitle(ACLocalizedString("chart_30days", nil), for: .normal)
        case .alltime:
            changeStatisticsDatesButton.setTitle(ACLocalizedString("chart_alltime", nil), for: .normal)
        }
    }
    
    /**
     Changes number of requests for specific button
     */
    private func changeTextForButton(with keyPath: String?){
        DispatchQueue.main.async {[weak self] in
            guard let self = self else { return }
            if keyPath == AEDefaultsRequests {
                let number = self.resources.sharedDefaults().integer(forKey: AEDefaultsRequests)
                self.requestsNumberLabel.text = "\(number)"
            } else if keyPath == AEDefaultsBlockedRequests {
                let number = self.resources.sharedDefaults().integer(forKey: AEDefaultsBlockedRequests)
                self.blockedNumberLabel.text = "\(number)"
            }
        }
    }
    
    /**
    Changes number of requests for all buttons
    */
    private func updateTextForButtons(){
        let requestsNumber = resources.sharedDefaults().integer(forKey: AEDefaultsRequests)
        requestsNumberLabel.text = "\(requestsNumber)"
        
        let blockedNumber = resources.sharedDefaults().integer(forKey: AEDefaultsBlockedRequests)
        blockedNumberLabel.text = "\(blockedNumber)"
    }
    
    private func changeProtectionStatusLabel(){
        protectionStatusLabel.text = complexText
    }
    
    /**
     Called when "requests" button tapped
     */
    private func chooseRequest(){
        chartModel.chartRequestType = .requests
        
        requestsNumberLabel.alpha = 1.0
        blockedNumberLabel.alpha = 0.5
        
        requestsTextLabel.alpha = 1.0
        blockedTextLabel.alpha = 0.5
    }
    
    /**
    Called when "blocked" button tapped
    */
    private func chooseBlocked(){
        chartModel.chartRequestType = .blocked
        
        requestsNumberLabel.alpha = 0.5
        blockedNumberLabel.alpha = 1.0
        
        requestsTextLabel.alpha = 0.5
        blockedTextLabel.alpha = 1.0
    }
    
    /**
     Adds observers to controller
     */
    private func addObservers(){

        themeNotificationToken = NotificationCenter.default.observe(name: NSNotification.Name( ConfigurationService.themeChangeNotification), object: nil, queue: OperationQueue.main) {[weak self] (notification) in
            self?.updateTheme()
        }
        
        appWillEnterForeground = NotificationCenter.default.observe(name: UIApplication.willEnterForegroundNotification, object: nil, queue: nil, using: {[weak self] (notification) in
            self?.checkProtectionStates()
        })
        
        resources.sharedDefaults().addObserver(self, forKeyPath: AEDefaultsRequests, options: .new, context: nil)
        
        resources.sharedDefaults().addObserver(self, forKeyPath: AEDefaultsBlockedRequests, options: .new, context: nil)
        
        let proObservation = configuration.observe(\.proStatus) {[weak self] (_, _) in
            guard let self = self else { return }
            self.observeProStatus()
        }
        
        let contenBlockerObservation = configuration.observe(\.contentBlockerEnabled) {[weak self] (_, _) in
            guard let self = self else { return }
            self.observeContentBlockersState()
        }

        observations.append(proObservation)
        observations.append(contenBlockerObservation)
        
        configuration.checkContentBlockerEnabled()
    }
    
    /**
     Removes observers from controller
     */
    private func removeObservers(){
        resources.sharedDefaults().removeObserver(self, forKeyPath: AEDefaultsRequests, context: nil)
        
        resources.sharedDefaults().removeObserver(self, forKeyPath: AEDefaultsBlockedRequests, context: nil)
    }
    
    /**
     Starts to rotate refresh button
     */
    private func updateStarted(){
        iconButton?.isUserInteractionEnabled = false
        updateButton.customView?.rotateImage(isNedeed: true)
    }
    
    /**
     Stops to rotate refresh button
     */
    private func updateEnded(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: {[weak self] in
            self?.iconButton?.isUserInteractionEnabled = true
            self?.updateButton.customView?.rotateImage(isNedeed: false)
            self?.changeProtectionStatusLabel()
        })
    }
    
    /**
     States views by pro status
     */
    private func observeProStatus(){
        DispatchQueue.main.async {[weak self] in
            guard let self = self else { return }
            
            self.getProView.isHidden = self.proStatus
            self.statisticsStackView.isHidden = !self.proStatus
            self.changeStatisticsDatesButton.isHidden = !self.proStatus
            self.systemProtectionButton.buttonIsOn = self.proStatus
        }
    }
    
    /**
    Checks state of safari, system and complex protection
     and updates UI
    */
    private func checkProtectionStates(){
        complexProtection.getAllStates {[weak self] (safariEnabled, systemEnabled, complexEnabled) in
            guard let self = self else { return }

            DispatchQueue.main.async {
                
                
                self.safariProtectionButton.buttonIsOn = safariEnabled
                self.systemProtectionButton.buttonIsOn = systemEnabled
                self.chartView.isEnabled = systemEnabled
                self.complexProtectionSwitch.setOn(on: complexEnabled)
                
                let enabledText = complexEnabled ? ACLocalizedString("protection_enabled", nil) : ACLocalizedString("protection_disabled", nil)
                self.protectionStateLabel.text = enabledText
                
                if safariEnabled && systemEnabled {
                    self.complexText = ACLocalizedString("complex_enabled", nil)
                } else if !complexEnabled{
                    self.complexText = ACLocalizedString("complex_disabled", nil)
                } else if safariEnabled {
                    self.complexText = ACLocalizedString("safari_enabled", nil)
                } else if systemEnabled {
                    self.complexText = ACLocalizedString("system_enabled", nil)
                }
                self.protectionStatusLabel.text = self.complexText
                
                self.activityIndicator.stopAnimating()
            }
        }
    }
    
    /**
    Checks state of content blockers
     and updates UI
    */
    private func observeContentBlockersState() {
        let isIphone = UIDevice.current.userInterfaceIdiom == .phone
        
        let optionalEnabled = configuration.contentBlockerEnabled
        guard let enabledBlockers = optionalEnabled else {
            return
        }
        
        var allEnabled = true
        for blocker in enabledBlockers {
            allEnabled = allEnabled && blocker.value
        }
        
        DispatchQueue.main.async {[weak self] in
            self?.contentBlockerViewIphone.isHidden = !isIphone
            self?.contentBlockerViewIpad.isHidden = isIphone
        }
        
        if !allEnabled {
            showContentBlockersInfo()
        } else {
            hideContentBlockersInfo()
        }
    }
    
    /**
     Shows content blockers info in the bottom of the screen
     */
    private func showContentBlockersInfo(){
        let isIphone = UIDevice.current.userInterfaceIdiom == .phone
        
        if isIphone {
            DispatchQueue.main.async {[weak self] in
                self?.contentBlockerViewIphone.isHidden = false
                UIView.animate(withDuration: 0.5) {
                    self?.contentBlockerViewConstraint.constant = 64.0
                }
            }
        } else {
            DispatchQueue.main.async {[weak self] in
                self?.contentBlockerViewIpad.alpha = 0.0
                self?.contentBlockerViewIpad.isHidden = false
                UIView.animate(withDuration: 0.5) {
                    self?.contentBlockerViewIpad.alpha = 1.0
                }
            }
        }
    }
    
    /**
     Hides content blockers info in the bottom of the screen
     */
    private func hideContentBlockersInfo(){
        let isIphone = UIDevice.current.userInterfaceIdiom == .phone
        if isIphone {
            DispatchQueue.main.async {[weak self] in
                UIView.animate(withDuration: 0.5, animations: {[weak self] in
                    self?.contentBlockerViewConstraint.constant = 0.0
                }) {[weak self] (success) in
                    self?.contentBlockerViewIphone.isHidden = true
                }
            }
        } else {
            DispatchQueue.main.async {[weak self] in
                UIView.animate(withDuration: 0.5, animations: {[weak self] in
                    self?.contentBlockerViewIpad.alpha = 0.0
                }) {[weak self] (success) in
                    self?.contentBlockerViewIpad.isHidden = true
                }
            }
        }
    }
    
    @objc private func handleContentBlockersView(_ gestureRecognizer: UIPanGestureRecognizer) {
        let translation = gestureRecognizer.translation(in: self.view)
        let x = translation.x
        let y = translation.y
        let gestureViewX = gestureRecognizer.view?.center.x ?? 0.0
        let gestureViewY = gestureRecognizer.view?.center.y ?? 0.0
        
        if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
            contentBlockerViewIpad.center = CGPoint(x: gestureViewX + x, y: gestureViewY + y)
            gestureRecognizer.setTranslation(CGPoint.zero, in: self.view)
        }
    }
    
    private func showOnboarding() {
        performSegue(withIdentifier: showOnboardingSegueId, sender: self)
    }
    
    func callOnready() {
        onReady?()
        onReady = nil
    }

}