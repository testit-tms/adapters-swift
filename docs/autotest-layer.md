# Autotest layer (test pyramid)

The adapter can set the **test pyramid layer** on an autotest card in Test IT. The layer is declared **in test code only** — not via `testit.properties` or environment variables.

After a run, the autotest card shows:

- the layer name (for example `API`, `E2E`);
- source **Run** (set by the adapter), distinct from Manual / Rule / Report.

## Declaration in XCTest

Use `TestItContextBuilder.Layer(_:)` in `setUp()` or at the start of the test method:

```swift
import testit_adapters_swift

final class UserApiTests: TestItTestCase {

    override func setUp() {
        super.setUp()
        TestItContextBuilder()
            .Layer(TestLayers.API)
            .build(self)
    }

    func testCreateUser() {
        // ...
    }
}
```

Custom layer names are allowed:

```swift
TestItContextBuilder()
    .Layer("my-custom-layer")
    .build(self)
```

If you omit `.Layer(...)`, the adapter does not send `layer` to TMS.

## Recommended constants

```swift
TestLayers.E2E
TestLayers.UI
TestLayers.API
TestLayers.CONTRACT
TestLayers.INTEGRATION
TestLayers.COMPONENT
TestLayers.UNIT
```

Any other non-empty string is accepted without validation.

## API behaviour

| Scenario | Adapter behaviour |
|----------|-------------------|
| Layer set in test | **Create:** send `layer: { name, source: Run }` |
| Layer set in test | **Update:** send `layer` + `resetLayer: false` |
| Layer not set | send `resetLayer: false`; do **not** send `layer` |

Layer is independent from autotest labels, tags, and test run tags/links.

## What is not supported

- Default layer for all tests via config or env
- Layer on test run or test result entities
- Resetting an existing TMS layer when the test omits `.Layer(...)` (`resetLayer` is always `false`)

See also: [changes-autotest-layer.md](changes-autotest-layer.md).
