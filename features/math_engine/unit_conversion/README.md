# Unit conversion

> Status: ⏳ later phase

- **Input:** value + units
- **Output:** converted value

## JSON shape

Input: `{ "value": 100, "from_unit": "km", "to_unit": "miles" }`
Output: `{ "value": 62.137, "from_unit": "km", "to_unit": "miles" }`

## Notes

- Built on `pint`. Uses `pint.Quantity(value, unit)` rather than `value * ureg(unit)` — the latter raises `OffsetUnitCalculusError` on affine units like `degF`/`degC` (temperature conversion needs an offset, not just a multiplicative factor).
- Tested: `100 km -> 62.14 miles`, `32 degF -> 0 degC`, `1 hour -> 3600 seconds`, `5 kg -> 11.02 lb` — all correct.
