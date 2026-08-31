# Changes: autotest layer support (Swift adapter)

## Summary

Optional **test pyramid layer** metadata can be declared in XCTest code and is sent to TMS when creating or updating autotests.

## Added

| Item | Description |
|------|-------------|
| `TestLayers` | Recommended layer name constants (`E2E`, `UI`, `API`, …) |
| `TestItContextBuilder.Layer(_:)` | Declares layer on a test method |
| `TestResultCommon.layer` | Internal optional string field |
| `Converter.layerToApiModel(from:)` | Maps to `LayerApiModel(name:, source: .run)` |
| `docs/autotest-layer.md` | User documentation |
| `Tests/ConverterLayerTests.swift` | Unit tests for create/update/failed-update paths |

## API mapping

- **Create autotest:** include `layer` only when the test declares a non-empty layer.
- **Update autotest:** always `resetLayer: false`; include `layer` only when declared.
- **Failed-test minimal update:** still applies layer from test annotation when present.

## Not changed

- No config/env/CLI layer defaults.
- No layer on test run or test result payloads.
- No whitelist validation of layer names.
- Labels, tags, and test run metadata behaviour unchanged.

## Migration

No breaking changes for existing tests. Tests without `.Layer(...)` behave as before; TMS layer is not reset on update.
