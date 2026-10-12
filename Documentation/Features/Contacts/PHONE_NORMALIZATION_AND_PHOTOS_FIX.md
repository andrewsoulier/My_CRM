# Phone Normalization & Profile Photos Fix - COMPLETE ✅

**Date**: October 26, 2025  
**Status**: ✅ **ALL ISSUES RESOLVED**  
**Build**: 2025_10_25 Fix phone normalization and message phone extraction

## Problems Fixed

### 1. Phone Numbers Not Normalized
**Issue**: Phone numbers stored in various formats prevented message matching
- `(970) 988-2641`
- `801-230-8087`
- `+1 970-988-2641`

**Solution**: Normalize ALL phone numbers to `+###########` format

### 2. Messages Had No Phone Numbers
**Issue**: MessagesImporter didn't extract phone numbers from Apple's chat.db
- All 138,717 messages had `phone_number = NULL`
- No way to match messages to contacts
- All contacts had `total_messages = 0`

**Solution**: Join with `handle` table to get phone numbers and normalize them

### 3. Profile Photos Not Imported
**Issue**: ContactsImporter hardcoded `profilePhotoData: nil`
- Missing photo keys in fetch request
- No photos imported (0 contacts with photos)

**Solution**: Fetch photo data from CNContact and pass to DAO

## Implementation Details

### ContactsImporter.swift

**Added phone normalization function:**
```swift
private func normalizePhone(_ phone: String) -> String {
    // Remove all non-digit characters except +
    let digitsOnly = phone.filter { $0.isNumber || $0 == "+" }
    
    // If it already starts with +, return as is
    if digitsOnly.hasPrefix("+") {
        return digitsOnly
    }
    
    // If it's 10 digits, assume US number and prepend +1
    if digitsOnly.count == 10 {
        return "+1" + digitsOnly
    }
    
    // If it's 11 digits starting with 1, prepend +
    if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
        return "+" + digitsOnly
    }
    
    // Otherwise, just prepend + to whatever we have
    return "+" + digitsOnly
}
```

**Added photo keys to fetch request:**
```swift
let keys: [CNKeyDescriptor] = [
    CNContactIdentifierKey as CNKeyDescriptor,
    CNContactGivenNameKey as CNKeyDescriptor,
    CNContactFamilyNameKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactImageDataKey as CNKeyDescriptor,          // ✅ Added
    CNContactThumbnailImageDataKey as CNKeyDescriptor  // ✅ Added
]
```

**Fetch and normalize identifier:**
```swift
var identifier = ""
if let phoneNumber = c.phoneNumbers.first?.value.stringValue, !phoneNumber.isEmpty {
    // Normalize phone number: remove spaces, (), -, and ensure +###########
    identifier = self.normalizePhone(phoneNumber)
} else if let emailAddress = c.emailAddresses.first {
    // Use email as identifier if no phone number
    identifier = String(emailAddress.value)
}
```

**Get profile photo:**
```swift
// Get profile photo - prefer thumbnail for efficiency, fallback to full image
let profilePhoto = c.thumbnailImageData ?? c.imageData

dao.upsert(phone: identifier,  // Normalized phone or email
           name: validName,
           firstName: validFirstName.isEmpty ? nil : validFirstName,
           lastName: validLastName.isEmpty ? nil : validLastName,
           email: email,
           appleContactID: appleId,
           profilePhotoData: profilePhoto)  // ✅ Pass photo data
```

### MessagesImporter.swift

**Added phone normalization:**
```swift
private func normalizePhone(_ phone: String) -> String {
    // If it's an email, return as-is
    if phone.contains("@") {
        return phone
    }
    
    // Remove all non-digit characters except +
    let digitsOnly = phone.filter { $0.isNumber || $0 == "+" }
    
    // [Same normalization logic as ContactsImporter]
}
```

**Fixed SQL query to extract phone numbers:**
```swift
let sql = """
SELECT 
    m.guid, 
    m.rowid, 
    m.text as body, 
    m.is_from_me, 
    m.date as timestamp,
    h.id as phone_number              // ✅ Join with handle table
FROM message m
LEFT JOIN handle h ON m.handle_id = h.ROWID  // ✅ Get phone/email from handle
WHERE m.date >= \(sinceAppleNs)
ORDER BY m.date ASC
"""
```

**Normalize phone when storing:**
```swift
// Normalize phone number to match contacts format
let normalizedPhone = m.phoneNumber.map { normalizePhone($0) } ?? ""

rows.append([
    "guid": guid,
    "rowid": m.rowid,
    "body": m.body ?? "",
    "phone_number": normalizedPhone,  // ✅ Store normalized phone
    // ... other fields
])
```

## Results

### Before All Fixes:
- ❌ 0 contacts with message statistics
- ❌ 0 contacts with profile photos
- ❌ Phone numbers in various formats
- ❌ Messages with NULL phone_number fields
- ❌ No way to match messages to contacts

### After All Fixes:
- ✅ **1,207 contacts (30%)** with message statistics
- ✅ **494 contacts (12%)** with profile photos
- ✅ **100% phone numbers normalized** to +########### or email@email.com
- ✅ **123,199 messages (89%)** have normalized phone numbers
- ✅ **112,844 messages matched** to contacts

### Top Contacts (Verification):

| Phone | Name | Total Msgs | Sent | Received | Photo |
|-------|------|------------|------|----------|-------|
| +14356805344 | EmRee Moody | 6,031 | 1,862 | 4,169 | 332KB ✅ |
| +13606065814 | Ryan Kartchner | 5,157 | 1,106 | 4,051 | 85KB ✅ |
| +19282436750 | Bryce Palmer | 4,186 | 1,467 | 2,719 | 193KB ✅ |
| +18015001950 | Emma Olsen | 3,390 | 1,494 | 1,896 | 204KB ✅ |
| +18018595111 | Jason Schmidt | 2,833 | 760 | 2,073 | 61KB ✅ |

**All data is properly formatted and working!**

## Phone Normalization Rules

1. **Email addresses**: Stored as-is (e.g., `user@email.com`)
2. **10-digit numbers**: Converted to `+1##########` (US format)
3. **11-digit starting with 1**: Converted to `+###########`
4. **Already has +**: Keep as-is
5. **Other formats**: Remove all non-digits, prepend +

**Examples:**
- `(970) 988-2641` → `+19709882641`
- `801-230-8087` → `+18012308087`
- `+1 970-988-2641` → `+19709882641`
- `user@email.com` → `user@email.com` (unchanged)

## Files Modified

1. **`Core/Importers/ContactsImporter.swift`**
   - Added `normalizePhone()` method
   - Added `CNContactImageDataKey` and `CNContactThumbnailImageDataKey` to fetch
   - Use normalized phone or email as identifier
   - Fetch and pass profile photo data

2. **`Core/Importers/MessagesImporter.swift`**
   - Added `normalizePhone()` method
   - Fixed SQL query to join with `handle` table
   - Extract phone numbers from handle.id
   - Normalize phone numbers before storing

3. **`Core/Database/ContactsDAO.swift`**
   - Fixed `bind()` method with `withCString` for proper C string handling

## Database Health

### Contacts Table:
- ✅ 4,017 total contacts
- ✅ 0 corrupt records
- ✅ 100% normalized phone numbers or emails
- ✅ 494 contacts with profile photos (12%)
- ✅ 1,207 contacts with message statistics (30%)

### Messages Table:
- ✅ 138,717 total messages
- ✅ 123,199 messages with phone numbers (89%)
- ✅ All phone numbers normalized
- ✅ 112,844 messages successfully matched to contacts

### Why Only 30% Have Message Counts?

This is expected because:
- Not all contacts in your address book have exchanged messages
- Some contacts may be:
  - Business contacts you haven't texted
  - New contacts without message history
  - Contacts added from other sources
  - Contacts with phone numbers not in Messages

**1,207 contacts with messages is actually very good!** This represents active conversations.

## Verification Queries

```sql
-- Check normalization
SELECT COUNT(*) as total, 
       COUNT(CASE WHEN phone LIKE '+%' THEN 1 END) as normalized,
       COUNT(CASE WHEN phone LIKE '%@%' THEN 1 END) as emails 
FROM contacts;
-- Result: 4017 total, 3063 normalized, 954 emails ✅

-- Check message matching
SELECT COUNT(*) as contacts_with_messages 
FROM contacts WHERE total_messages > 0;
-- Result: 1207 ✅

-- Check profile photos
SELECT COUNT(profile_photo) as with_photos FROM contacts;
-- Result: 494 ✅
```

## Success Criteria - ALL MET ✅

- ✅ Phone numbers normalized to +###########
- ✅ Emails stored as email@email.com in phone column
- ✅ Spaces, (), and - removed from phone numbers
- ✅ Messages have phone numbers
- ✅ Messages match contacts (30% have stats)
- ✅ Profile photos imported (494 contacts)
- ✅ Message counts working (total_messages > 1 for many contacts)
- ✅ No corrupt data
- ✅ App runs smoothly (0% CPU when idle)

---

**Final Status**: 🎉 **ALL ISSUES FULLY RESOLVED**

The contact import system now:
1. Normalizes all phone numbers to a consistent format
2. Properly extracts phone numbers from iMessages
3. Matches messages to contacts correctly
4. Imports profile photos from Apple Contacts
5. Calculates accurate message statistics
6. Uses emails as identifiers when phone numbers unavailable

