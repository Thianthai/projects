CLASS zcl_dms_utility DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_upload_result,
        object_id   TYPE string,  " DMS Object ID ของไฟล์ที่ถูกอัปโหลด
        object_name TYPE string,
      END OF ty_upload_result.

    CLASS-METHODS:

      "! Upload a document file to DMS repository
      "! @parameter iv_file_name | File name with extension e.g. invoice.pdf
      "! @parameter iv_mime_type | MIME type e.g. application/pdf, application/msword
      "! @parameter iv_content   | File binary content as xstring
      "! @parameter rs_result    | Upload result containing DMS Object ID
      upload_document
        IMPORTING
          iv_file_name     TYPE string
          iv_mime_type     TYPE string
          iv_content       TYPE xstring
        RETURNING
          VALUE(rs_result) TYPE ty_upload_result
        RAISING
          zcl_dms_error,

      "! Link an uploaded DMS document to a SAP business object (e.g. FI Document)
      "! Must be called after upload_document to get iv_object_id
      "! @parameter iv_object_id | DMS Object ID from upload_document result
      "! @parameter iv_bo_type   | SAP Business Object type e.g. BKPF, BUS2012
      "! @parameter iv_bo_key    | Business Object key
      link_to_business_object
        IMPORTING
          iv_object_id TYPE string
          iv_bo_type   TYPE string
          iv_bo_key    TYPE string
        RAISING
          zcl_dms_error.

  PRIVATE SECTION.

    " ============================================================
    " HARD-CODED DMS Configuration — Replace with actual values
    " after DMS instance is provisioned
    " ============================================================

    CONSTANTS:
      "! [REPLACE] SM59 HTTP Destination name pointing to BTP DMS service
      "!           Create in SM59: Connection Type = G (HTTP to External Server)
      c_destination       TYPE rfcdest VALUE 'DMS_BTP',

      "! [REPLACE] DMS Repository ID from DMS Configuration (SDM cockpit)
      c_repository_id     TYPE string  VALUE 'repo-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',

      "! [REPLACE] CMIS Object Type ID — usually 'cmis:document' unless custom type defined
      c_object_type_id    TYPE string  VALUE 'cmis:document',

      "! [REPLACE] Relationship type defined in DMS for linking to SAP Business Object
      "!           Check DMS Admin UI > Repository > Relationship Types
      c_relationship_type TYPE string  VALUE 'sap:relatesToBusinessObject'.

    CLASS-METHODS:

      "! [Standard ABAP — fallback: CL_HTTP_DESTINATION_PROVIDER not available in this system]
      "! Create IF_HTTP_CLIENT via SM59 HTTP destination
      create_http_client
        RETURNING
          VALUE(ro_client) TYPE REF TO if_http_client
        RAISING
          zcl_dms_error,

      "! Send HTTP request and return response body as string
      send_request
        IMPORTING
          io_client       TYPE REF TO if_http_client
          iv_method       TYPE string
          iv_path         TYPE string
          iv_content_type TYPE string OPTIONAL
          iv_body         TYPE xstring OPTIONAL
        RETURNING
          VALUE(rv_response) TYPE string
        RAISING
          zcl_dms_error,

      "! Build multipart/form-data body for CMIS document creation (browser binding)
      build_multipart_body
        IMPORTING
          iv_file_name    TYPE string
          iv_mime_type    TYPE string
          iv_content      TYPE xstring
        EXPORTING
          ev_body         TYPE xstring
          ev_boundary     TYPE string,

      "! Extract string value from a simple flat JSON response by key
      "! e.g. get_json_value( iv_json = '{"objectId":"abc"}' iv_key = 'objectId' ) -> 'abc'
      get_json_value
        IMPORTING
          iv_json         TYPE string
          iv_key          TYPE string
        RETURNING
          VALUE(rv_value) TYPE string.

ENDCLASS.


CLASS zcl_dms_utility IMPLEMENTATION.

  METHOD upload_document.

    DATA(lo_client) = create_http_client( ).

    DATA: lv_body     TYPE xstring,
          lv_boundary TYPE string.

    build_multipart_body(
      EXPORTING
        iv_file_name = iv_file_name
        iv_mime_type = iv_mime_type
        iv_content   = iv_content
      IMPORTING
        ev_body      = lv_body
        ev_boundary  = lv_boundary ).

    " CMIS Browser Binding: POST to /browser/{repositoryId}/root
    DATA(lv_path)     = |/browser/{ c_repository_id }/root|.
    DATA(lv_response) = send_request(
      io_client       = lo_client
      iv_method       = 'POST'
      iv_path         = lv_path
      iv_content_type = |multipart/form-data; boundary={ lv_boundary }|
      iv_body         = lv_body ).

    " Parse objectId and name from CMIS JSON response
    " Response example: {"objectId":"abc-123","name":"invoice.pdf",...}
    rs_result-object_id   = get_json_value( iv_json = lv_response iv_key = 'objectId' ).
    rs_result-object_name = get_json_value( iv_json = lv_response iv_key = 'name' ).

    lo_client->close( ).

  ENDMETHOD.


  METHOD link_to_business_object.

    DATA(lo_client) = create_http_client( ).

    " CMIS Browser Binding: POST to /browser/{repositoryId}/root
    " with cmisaction=createRelationship to link document to business object
    DATA(lv_path) = |/browser/{ c_repository_id }/root|.

    " iv_bo_key format depends on DMS configuration — confirm with DMS Admin
    " e.g. for FI Document: "<BUKRS>.<BELNR>.<GJAHR>"
    DATA(lv_target_id) = |{ iv_bo_type }.{ iv_bo_key }|.

    DATA(lv_body_str) =
      |cmisaction=createRelationship|
      && |&propertyId[0]=cmis:objectTypeId|
      && |&propertyValue[0]={ c_relationship_type }|
      && |&propertyId[1]=cmis:sourceId|
      && |&propertyValue[1]={ iv_object_id }|
      && |&propertyId[2]=cmis:targetId|
      && |&propertyValue[2]={ lv_target_id }|.

    DATA(lv_body) = cl_abap_codepage=>convert_to(
      source   = lv_body_str
      codepage = 'UTF-8' ).

    send_request(
      io_client       = lo_client
      iv_method       = 'POST'
      iv_path         = lv_path
      iv_content_type = 'application/x-www-form-urlencoded'
      iv_body         = lv_body ).

    lo_client->close( ).

  ENDMETHOD.


  METHOD create_http_client.

    " [Standard ABAP fallback] CL_HTTP_DESTINATION_PROVIDER not available in this system
    " Using SM59 HTTP destination instead of Communication Arrangement
    " [REPLACE] Create destination c_destination in SM59:
    "           Connection Type = G, Host = <DMS host>, SSL = Active
    cl_http_client=>create_by_destination(
      EXPORTING
        destination              = c_destination
      IMPORTING
        client                   = ro_client
      EXCEPTIONS
        argument_not_found       = 1
        destination_not_found    = 2
        destination_no_authority = 3
        plugin_not_active        = 4
        internal_error           = 5
        OTHERS                   = 6 ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcl_dms_error
        EXPORTING
          textid  = zcl_dms_error=>destination_error
          mv_info = |Cannot create HTTP client for SM59 destination: { c_destination }|.
    ENDIF.

  ENDMETHOD.


  METHOD send_request.

    io_client->request->set_method( iv_method ).
    io_client->request->set_header_field(
      name  = '~request_uri'
      value = iv_path ).

    IF iv_content_type IS NOT INITIAL.
      io_client->request->set_header_field(
        name  = 'Content-Type'
        value = iv_content_type ).
    ENDIF.

    IF iv_body IS NOT INITIAL.
      io_client->request->set_data( iv_body ).
    ENDIF.

    io_client->send(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        OTHERS                     = 3 ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcl_dms_error
        EXPORTING
          textid  = zcl_dms_error=>send_error
          mv_info = |HTTP send failed: { iv_method } { iv_path }|.
    ENDIF.

    io_client->receive(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4 ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcl_dms_error
        EXPORTING
          textid  = zcl_dms_error=>receive_error
          mv_info = |HTTP receive failed: { iv_method } { iv_path }|.
    ENDIF.

    DATA lv_status TYPE i.
    io_client->response->get_status(
      IMPORTING
        code = lv_status ).
    rv_response     = io_client->response->get_cdata( ).

    IF lv_status >= 400.
      RAISE EXCEPTION TYPE zcl_dms_error
        EXPORTING
          textid  = zcl_dms_error=>api_error
          mv_info = |HTTP { lv_status }: { rv_response }|.
    ENDIF.

  ENDMETHOD.


  METHOD build_multipart_body.

    " Generate unique boundary using timestamp
    ev_boundary = |DMS_BOUNDARY_{ sy-datum }{ sy-uzeit }|.

    " Part 1: CMIS properties (JSON) — tells DMS to create a document
    DATA(lv_props_json) =
      |\{"cmis:name":"{ iv_file_name }",|
      && |"cmis:objectTypeId":"{ c_object_type_id }"\}|.

    DATA(lv_part1) =
      |--{ ev_boundary }\r\n|
      && |Content-Disposition: form-data; name="propertyValues"\r\n|
      && |Content-Type: application/json;charset=utf-8\r\n\r\n|
      && |{ lv_props_json }\r\n|.

    " Part 2: cmisaction field
    DATA(lv_part2) =
      |--{ ev_boundary }\r\n|
      && |Content-Disposition: form-data; name="cmisaction"\r\n\r\n|
      && |createDocument\r\n|.

    " Part 3: file binary content
    DATA(lv_part3_header) =
      |--{ ev_boundary }\r\n|
      && |Content-Disposition: form-data; name="contentfile"; filename="{ iv_file_name }"\r\n|
      && |Content-Type: { iv_mime_type }\r\n\r\n|.

    DATA(lv_part3_footer) = |\r\n--{ ev_boundary }--\r\n|.

    " Concatenate all parts as xstring (preserve binary content intact)
    DATA(lv_prefix) = cl_abap_codepage=>convert_to(
      source   = lv_part1 && lv_part2 && lv_part3_header
      codepage = 'UTF-8' ).

    DATA(lv_suffix) = cl_abap_codepage=>convert_to(
      source   = lv_part3_footer
      codepage = 'UTF-8' ).

    ev_body = lv_prefix && iv_content && lv_suffix.

  ENDMETHOD.


  METHOD get_json_value.
    " Simple regex-based extraction for flat JSON strings
    " Not suitable for nested JSON — use XCO JSON library if complexity grows
    DATA(lv_pattern) = |"{ iv_key }"\\s*:\\s*"([^"]*)"|.

    FIND FIRST OCCURRENCE OF REGEX lv_pattern
      IN iv_json
      SUBMATCHES rv_value.

  ENDMETHOD.

ENDCLASS.
