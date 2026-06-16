# ZCL_DMS_UTILITY — API Reference

## Prerequisites

### 1. SM59 Destination: `DMS_BTP`

| Field | Value |
|-------|-------|
| Connection Type | G (HTTP Connection to External Server) |
| Host | `<your-dms-instance>.hana.ondemand.com` |
| Path Prefix | `/` |
| SSL | Active |
| Logon / Security | OAuth 2.0 (via OAuth Client in SOAUTH2) |

### 2. Required ABAP Objects

- `ZCX_DMS_ERROR` — Custom exception class
- Message Class `ZDMS` with messages 001–006

---

## Methods

### `UPLOAD_DOCUMENT`

```abap
DATA(lv_object_id) = zcl_dms_utility=>upload_document(
  iv_repository_id = 'my-repo-id'
  iv_file_name     = 'invoice.pdf'
  iv_mime_type     = 'application/pdf'
  iv_content       = lv_xstring_content ).
```

**Returns**: `rv_object_id` — DMS Object ID ของไฟล์ที่อัปโหลด

---

### `DOWNLOAD_DOCUMENT`

```abap
DATA(lv_content) = zcl_dms_utility=>download_document(
  iv_repository_id = 'my-repo-id'
  iv_object_id     = 'abc-123-def' ).
```

**Returns**: `rv_content` — ไฟล์เป็น `xstring`

---

### `LINK_TO_BUSINESS_OBJECT`

```abap
zcl_dms_utility=>link_to_business_object(
  iv_repository_id   = 'my-repo-id'
  iv_document_id     = 'abc-123-def'
  iv_business_object = 'BUS2012'    " Purchase Order
  iv_object_key      = '4500000123' ).
```

Business Object Types ที่ใช้บ่อย:

| Type | Description |
|------|-------------|
| `BUS2012` | Purchase Order |
| `BUS2081` | Goods Receipt |
| `BKPF` | Accounting Document |
| `VBAK` | Sales Order |

---

### `SEARCH_DOCUMENTS`

```abap
" ค้นหาด้วย CMIS Query
DATA(lt_docs) = zcl_dms_utility=>search_documents(
  iv_repository_id = 'my-repo-id'
  iv_query         = 'SELECT * FROM cmis:document WHERE cmis:name LIKE ''invoice%''' ).

" ค้นหาจาก Business Object
DATA(lt_docs) = zcl_dms_utility=>search_documents(
  iv_repository_id   = 'my-repo-id'
  iv_business_object = 'BUS2012'
  iv_object_key      = '4500000123' ).
```

**Returns**: `rt_documents` — Table of `ty_document`

```abap
TYPES: BEGIN OF ty_document,
  object_id   TYPE string,
  name        TYPE string,
  mime_type   TYPE string,
  size        TYPE i,
  created_at  TYPE string,
  modified_at TYPE string,
END OF ty_document.
```

---

## Error Handling

```abap
TRY.
    DATA(lv_id) = zcl_dms_utility=>upload_document( ... ).
  CATCH zcx_dms_error INTO DATA(lo_err).
    MESSAGE lo_err->mv_info TYPE 'E'.
ENDTRY.
```

| Exception TextID | Situation |
|-----------------|-----------|
| `destination_error` | SM59 Destination ไม่พบหรือไม่มีสิทธิ์ |
| `send_error` | ส่ง HTTP Request ไม่ได้ |
| `receive_error` | รับ HTTP Response ไม่ได้ |
| `auth_error` | HTTP 401/403 — ตรวจสอบ OAuth |
| `not_found` | HTTP 404 — Repository หรือ Document ไม่พบ |
| `api_error` | HTTP 4xx/5xx อื่นๆ |
