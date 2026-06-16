# ABAP Utility Class for DMS

SAP Document Management Service (DMS) on SAP BTP — ABAP utility class สำหรับจัดการเอกสารผ่าน REST API

## Project Overview

- **Target**: SAP DMS REST API (SAP BTP)
- **HTTP Client**: `CL_HTTP_CLIENT` (New, SAP_BASIS 7.54+)
- **Main Class**: `ZCL_DMS_UTILITY`

## Features

| Method | Description |
|--------|-------------|
| `UPLOAD_DOCUMENT` | อัปโหลดไฟล์เข้า DMS Repository |
| `DOWNLOAD_DOCUMENT` | ดาวน์โหลดไฟล์จาก DMS |
| `LINK_TO_BUSINESS_OBJECT` | ผูก Document กับ Business Object (PO, Invoice, etc.) |
| `SEARCH_DOCUMENTS` | ค้นหาและแสดงรายการ Document |

## DMS API Endpoints (SAP BTP)

Base URL configured via RFC Destination or environment variable.

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Upload | POST | `/browser/{repositoryId}/root` |
| Download | GET | `/browser/{repositoryId}/root/{objectId}` |
| Link (Relationship) | POST | `/sdm/v1/repositories/{repositoryId}/documents/{documentId}/links` |
| Search | GET | `/browser/{repositoryId}/root?cmisselector=query` |

## File Structure

```
dms/
├── CLAUDE.md
├── src/
│   ├── zcl_dms_utility.clas.abap        # Main class implementation
│   ├── zcl_dms_utility.clas.locals_def.abap  # Local type definitions
│   └── zcl_dms_utility.clas.testclasses.abap # Unit tests
└── docs/
    └── api_reference.md
```

## Development Notes

- ใช้ Destination (SM59) สำหรับ Base URL และ OAuth token
- Error handling ผ่าน `cx_http_no_current_session` และ custom exception
- Response parse ด้วย `/ui2/cl_json`
