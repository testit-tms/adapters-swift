import XCTest
import Dispatch


// https://developer.apple.com/documentation/xctest/xctestobservation
class OverallLifecycleObserver: NSObject, XCTestObservation {

    // Статический экземпляр синглтона
    static let shared = OverallLifecycleObserver()

    private var writer: TestItWriter?
    private var appPropertiesInitialized = false
    private var writerInitialized = false // Дополнительный флаг для writer
    private var beforeAllCalled = false

    // Хранилище для XCTIssue текущего теста
    private var currentTestBodyIssues: [XCTIssue] = []
    private var currentFixtureIssues: [XCTIssue] = []
    private var currentTestCaseName: String? // Для связи issue с конкретным тестом

    // Контекст выполнения для setUp и tearDown
    private var currentTestCaseInSetUp: XCTestCase?
    private var currentTestCaseInTearDown: XCTestCase?

    // Приватный инициализатор, чтобы экземпляр создавался только через OverallLifecycleObserver.shared
    private override init() {
        
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
        print("OverallLifecycleObserver.shared initialized and registered. Setup will occur based on XCTest lifecycle events.")
    }

    deinit {
        // XCTestObservationCenter хранит слабую ссылку, так что это может и не понадобиться,
        // если shared будет жить все время. Но для полноты.
        XCTestObservationCenter.shared.removeTestObserver(self)
        print("OverallLifecycleObserver.shared deinitialized and removed.")
    }


    // Этот метод вызывается перед запуском первого теста в бандле
    // not called!
    func testBundleWillStart(_ testBundle: Bundle) {
        print("[OverallLifecycleObserver SHARED]: Attempting setup in testBundleWillStart with bundle: \(testBundle.bundleURL.lastPathComponent)")
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        print("[OverallLifecycleObserver SHARED]: Test suite will start: \(testSuite.name)")
        // Если зависимости еще не настроены (например, testBundleWillStart не сработал)
        if !appPropertiesInitialized || !writerInitialized {
            print("[OverallLifecycleObserver SHARED]: Dependencies not yet fully initialized, attempting setup via testSuiteWillStart.")
            // Пытаемся найти .xctest бандл, так как Bundle(for: type(of: testSuite)) может быть не тем
            if let xctestBundle = findXCTestBundle() {
                setupDependencies(using: xctestBundle, isPreferredBundle: false) // false, так как это fallback
            } else {
                // Если не нашли .xctest, попробуем с бандлом сьюты, но это менее надежно
                let suiteBundle = Bundle(for: type(of: testSuite))
                print("[OverallLifecycleObserver SHARED]: .xctest bundle not found, falling back to suiteBundle: \(suiteBundle.bundleURL.lastPathComponent) for setup.")
                setupDependencies(using: suiteBundle, isPreferredBundle: false)
            }
        }

        // on before all (testSuite)
        if !beforeAllCalled {
            let success = waitForAsyncTask {
                guard let strongWriter = self.writer else {
                    print("[OverallLifecycleObserver SHARED]: ERROR from testSuiteWillStart Task - Writer is nil.")
                    return
                }
                await strongWriter.onBeforeAll()
                self.beforeAllCalled = true
            }
            print("[OverallLifecycleObserver SHARED]: testSuiteWillStart - onBeforeAll completion success: \(success)")
        }
    }


    // Этот метод вызывается ПОСЛЕ завершения ВСЕХ тестов в бандле
    func testBundleDidFinish(_ testBundle: Bundle) {
        print("-------------------------------------")
        print("[OverallLifecycleObserver SHARED]: >>> All tests in the bundle did finish! <<<: \(testBundle.bundleURL.lastPathComponent)")
        print("-------------------------------------")
        let success = waitForAsyncTask {
            guard let strongWriter = self.writer else {
                print("[OverallLifecycleObserver SHARED]: ERROR from testBundleDidFinish Task - Writer is nil.")
                return
            }
            await strongWriter.onAfterAll()
        }
        print("[OverallLifecycleObserver SHARED]: testBundleDidFinish - onAfterAll completion success: \(success)")
    }
    
    // Остальные методы протокола XCTestObservation...
    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        print("[OverallLifecycleObserver SHARED]: Test suite did finish: \(testSuite.name)")
    }

    // looks like the same as TestItXCTestCase.invokeTest()
    func testCaseWillStart(_ testCase: XCTestCase) {
        print("[OverallLifecycleObserver SHARED]: Test case will start: \(testCase.name)")

        // Очищаем перед новым тестом
        self.currentTestBodyIssues = []
        self.currentFixtureIssues = []
        self.currentTestCaseName = testCase.name

        let success = waitForAsyncTask {
            print("[OverallLifecycleObserver SHARED] Task for testCaseWillStart: Calling writer.onTestWillStart for test \(testCase.name)...")
            // Задержка удалена, так как не была частью запроса на откат к waitForAsyncTask
            guard let strongWriter = self.writer else {
                print("[OverallLifecycleObserver SHARED]: ERROR from testCaseWillStart Task - Writer is nil.")
                return
            }
            await strongWriter.onTestWillStart(for: testCase)
            print("[OverallLifecycleObserver SHARED] Task for testCaseWillStart: writer.onTestWillStart completed for test \(testCase.name).")
        }
        print("[OverallLifecycleObserver SHARED]: testCaseWillStart - onTestWillStart completion success: \(success)")
    }

    // automatically in both success and failure cases
    func testCaseDidFinish(_ testCase: XCTestCase) {
        print("[OverallLifecycleObserver SHARED]: Test case did finish: \(testCase.name)")
        let finishTime = Date() // Фиксируем время завершения теста

        waitForAsyncTask {
            if let strongWriter = self.writer {
                let fixtureService = strongWriter.fixtureService
                // Завершаем before-фикстуру (setUp)
                // Если recordFailureInCurrentFixture уже пометил ее как failed и finished, этот вызов не перезапишет статус.
                // Если ошибок не было, она будет помечена как passed.
                fixtureService.completeCurrentBeforeFixture(for: testCase, status: .passed, stopTime: finishTime, issue: nil)

                // Завершаем after-фикстуру (tearDown)
                // Аналогично, если recordFailureInCurrentFixture уже пометил ее как failed и finished, статус не изменится.
                // Если ошибок не было, она будет помечена как passed.
                // Время остановки для tearDown также может быть finishTime, или более точное, если доступно.
                fixtureService.completeCurrentAfterFixture(for: testCase, status: .passed, stopTime: finishTime, issue: nil)

                // Передаем собранные issues и сам testCase в TestItWriter
                await strongWriter.onTestDidFinish(for: testCase, fixtureIssues: self.currentFixtureIssues, testBodyIssues: self.currentTestBodyIssues)
            } else {
                print("[OverallLifecycleObserver SHARED]: ERROR from testCaseDidFinish - Writer or FixtureService is nil, cannot complete fixtures or call onTestDidFinish.")
            }
            // Очищаем issues после обработки, готовимся к следующему тесту
            self.currentTestBodyIssues = []
            self.currentFixtureIssues = []
            self.currentTestCaseName = nil
        }
    }

    // Этот метод будет вызываться для каждого зарегистрированного XCTIssue
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        // Сохраняем все 'issue', возникшие во время теста
        // Убедимся, что issue относится к текущему обрабатываемому тесту, если currentTestCaseName используется для строгой проверки
        // В данном случае, просто добавляем, так как testCaseDidFinish обработает все для завершившегося теста
        print("[OverallLifecycleObserver SHARED]: Test case \(testCase.name) recorded issue: \(issue.compactDescription) at \(issue.sourceCodeContext.location?.fileURL.lastPathComponent ?? "unknown file"):\(issue.sourceCodeContext.location?.lineNumber ?? 0)")
        // self.currentTestIssues.append(issue) // Удаляем старое добавление

        let context: String
        var isFixtureFailure = false

        if let currentlyInSetUp = self.currentTestCaseInSetUp, currentlyInSetUp === testCase {
            context = "setUp"
            isFixtureFailure = true
            print("[OverallLifecycleObserver SHARED]: Issue recorded during setUp of \(testCase.name): \(issue.compactDescription)")
            self.currentFixtureIssues.append(issue) // Добавляем в fixtureIssues
            Task { // Асинхронный вызов, чтобы не блокировать testCase(_:didRecord:)
                await writer?.recordFixtureFailure(for: testCase, issue: issue, fixtureContext: context)
            }
        } else if let currentlyInTearDown = self.currentTestCaseInTearDown, currentlyInTearDown === testCase {
            context = "tearDown"
            isFixtureFailure = true
            print("[OverallLifecycleObserver SHARED]: Issue recorded during tearDown of \(testCase.name): \(issue.compactDescription)")
            self.currentFixtureIssues.append(issue) // Добавляем в fixtureIssues
            Task { // Асинхронный вызов
                await writer?.recordFixtureFailure(for: testCase, issue: issue, fixtureContext: context)
            }
        } else {
            // Ошибка произошла в теле теста, не в setUp или tearDown.
            self.currentTestBodyIssues.append(issue) // Добавляем в testBodyIssues
            print("[OverallLifecycleObserver SHARED]: Issue recorded in test body of \(testCase.name) (or outside specific setUp/tearDown context): \(issue.compactDescription)")
        }

        // Дальнейшая обработка isFixtureFailure может быть здесь или в writer
    }

    // not called on failing assertions
    func testCase(_ testCase: XCTestCase, didFailWith description: String, inFile filePath: String?, atLine lineNumber: Int) {
        print("[OverallLifecycleObserver SHARED]: Test case FAILED: \(testCase.name) - \(description)")
        waitForAsyncTask {
            if let strongWriter = self.writer {
                await strongWriter.onTestFailed(for: testCase)
            } else {
                print("[OverallLifecycleObserver SHARED]: ERROR from testCaseDidFinish - Writer is nil, cannot call onTestFailed.")
            }
        }
    }

    func onBeforeSetup(testCase: XCTestCase) {
        print("[OverallLifecycleObserver SHARED]: onBeforeSetup for test \(testCase.name)")
        self.currentTestCaseInSetUp = testCase // Устанавливаем контекст setUp
        // Your logic for before setup
        let success = waitForAsyncTask {
            guard let strongWriter = self.writer else {
                print("[OverallLifecycleObserver SHARED]: ERROR from onBeforeSetup Task - Writer is nil.")
                return
            }
            await strongWriter.onBeforeSetup(for: testCase)
        }
        print("[OverallLifecycleObserver SHARED]: onBeforeSetup - onBeforeSetup completion success: \(success)")
    }

    func onAfterSetup(testCase: XCTestCase) {
        print("[OverallLifecycleObserver SHARED]: onAfterSetup for \(testCase.name)")
        self.currentTestCaseInSetUp = nil // Сбрасываем контекст setUp
        // TODO: Возможно, здесь нужно вызвать writer?.onAfterSetup(for: testCase), если такая логика понадобится
    }

    func onBeforeTeardown(testCase: XCTestCase) {
        print("[OverallLifecycleObserver SHARED]: onBeforeTeardown for test \(testCase.name)")
        self.currentTestCaseInTearDown = testCase // Устанавливаем контекст tearDown
        // Your logic for before teardown
        let success = waitForAsyncTask {
            guard let strongWriter = self.writer else {
                print("[OverallLifecycleObserver SHARED]: ERROR from onBeforeTeardown Task - Writer is nil.")
                return
            }
            await strongWriter.onBeforeTeardown(for: testCase)
        }
        print("[OverallLifecycleObserver SHARED]: onBeforeTeardown - onBeforeTeardown completion success: \(success)")
    }

    func onAfterTeardown(testCase: XCTestCase) {
        print("[OverallLifecycleObserver SHARED]: onAfterTeardown for \(testCase.name)")
        self.currentTestCaseInTearDown = nil // Сбрасываем контекст tearDown
        // TODO: Возможно, здесь нужно вызвать writer?.onAfterTeardown(for: testCase), если такая логика понадобится
    }

    private func setupDependencies(using bundle: Bundle, isPreferredBundle: Bool) {
        // Если мы уже успешно инициализировались из предпочтительного бандла (из testBundleWillStart),
        // а сейчас пришел вызов с isPreferredBundle = false (из testSuiteWillStart), то ничего не делаем.
        if appPropertiesInitialized && !isPreferredBundle && writerInitialized {
            print("[OverallLifecycleObserver SHARED]: Dependencies already initialized, skipping setup from non-preferred bundle: \(bundle.bundleURL.lastPathComponent)")
            return
        }
        
        print("[OverallLifecycleObserver SHARED]: Running setupDependencies with bundle: \(bundle.bundleURL.lastPathComponent), isPreferred: \(isPreferredBundle)")

        if !appPropertiesInitialized {
            let propertiesFileName = "testit"
            let propertiesExtension = "properties"
            print("[OverallLifecycleObserver SHARED]: Attempting to load AppProperties from bundle: \(bundle.bundleURL.lastPathComponent)")
            guard let propertiesURL = bundle.url(forResource: propertiesFileName, withExtension: propertiesExtension) else {
                print("ПРЕДУПРЕЖДЕНИЕ: Файл \(propertiesFileName).\(propertiesExtension) не найден в бандле \(bundle.bundleIdentifier ?? bundle.bundleURL.lastPathComponent). AppProperties НЕ будут инициализированы этим бандлом.")
                return
            }
            do {
                let propertiesContent = try String(contentsOf: propertiesURL, encoding: .utf8)
                AppProperties.initialize(propertiesString: propertiesContent)
                print("[OverallLifecycleObserver SHARED]: AppProperties initialized. Content loaded from: \(propertiesURL.path)")
                appPropertiesInitialized = true
            } catch {
                 print("ПРЕДУПРЕЖДЕНИЕ: Ошибка чтения файла свойств \(propertiesURL.path): \(error). AppProperties НЕ будут инициализированы.")
                return
            }
        }

        if !writerInitialized {
            guard appPropertiesInitialized else {
                 print("[OverallLifecycleObserver SHARED]: ERROR - AppProperties not initialized, cannot create TestItWriter.")
                 return
            }
            writer = TestItWriter()
            writerInitialized = true
            print("[OverallLifecycleObserver SHARED]: TestItWriter initialized.")
        }
    }

    
    private func findXCTestBundle() -> Bundle? {
        for bundle in Bundle.allBundles {
            // Ищем бандлы с расширением .xctest
            if bundle.bundlePath.hasSuffix(".xctest") {
                print("[OverallLifecycleObserver SHARED]: Found .xctest bundle via findXCTestBundle: \(bundle.bundleURL.lastPathComponent)")
                return bundle
            }
        }
        print("[OverallLifecycleObserver SHARED]: No .xctest bundle found via findXCTestBundle.")
        return nil
    }


    /// Синхронно ожидает выполнения асинхронной операции с таймаутом.
    /// - Parameters:
    ///   - timeout: Максимальное время ожидания в секундах.
    ///   - operation: Асинхронная операция для выполнения.
    /// - Returns: `true`, если операция завершилась до таймаута, иначе `false`.
    private func waitForAsyncTask(
        timeout: TimeInterval = 100.0, // Таймаут по умолчанию
        operation: @escaping () async -> Void
    ) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            await operation()
            semaphore.signal() // Сигнализируем о завершении операции
        }

        // Ожидаем сигнала от семафора, но не дольше указанного таймаута
        let result = semaphore.wait(timeout: .now() + timeout)

        if result == .timedOut {
            print("[OverallLifecycleObserver SHARED]: waitForAsyncTask timed out after \(timeout) seconds.")
            return false
        }
        return true
    }
}
