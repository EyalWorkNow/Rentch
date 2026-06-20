# Property Addition Process - Bugs Found

## Critical Bugs

1. **NO MEDIA VALIDATION** - Property can be saved with ZERO photos/videos
2. **TRANSACTION TYPE HARDCODED** - Can only create rental listings, not sale listings (line 730)
3. **ROOMS CAN BE ZERO** - Slider allows 0 rooms (nonsensical)
4. **MEDIA UPLOAD FALLBACK DANGEROUS** - Uses local path if cloud upload fails (path won't exist on next session)
5. **GEOCODING FAILS SILENTLY** - Uses default Tel Aviv coords (32.0853, 34.7818) if geocoding fails
6. **NO EMPTY FIELD VALIDATION** - Accepts whitespace-only city/street
7. **PRICE CAN BE ZERO** - While technically allowed, might indicate data entry error
8. **NO DUPLICATE PROPERTY CHECK** - User can add same property multiple times
9. **INVALID ENTRY DATE ACCEPTED** - No validation of date format
10. **MISSING REQUIRED FIELD CHECKS** - Step 2 only validates size, but price and rooms should be validated too

