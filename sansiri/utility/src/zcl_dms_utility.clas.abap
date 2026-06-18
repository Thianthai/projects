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
          zcx_dms_error,

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
          zcx_dms_error.

  PRIVATE SECTION.

    " ============================================================
    " HARD-CODED DMS Configuration — Replace with actual values
    " after DMS instance is provisioned and Communication
    " Arrangement is configured in SAP BTP Cockpit / SAP S/4HANA
    " ============================================================

    CONSTANTS:
      "! [REPLACE] Communication Scenario ID defined in SE11 / SOAMANAGER
      c_comm_scenario     TYPE string VALUE 'ZDMS_COMM_SCENARIO',

      "! [REPLACE] DMS Repository ID from DMS Configuration (SDM cockpit)
      c_repository_id     TYPE string VALUE 'repo-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',

      "! [REPLACE] CMIS Object Type ID — usually 'cmis:document' unless custom type defined
      c_object_type_id    TYPE string VALUE 'cmis:document',

      "! [REPLACE] Relationship type defined in DMS for linking to SAP Business Object
      "!           Check DMS Admin UI > Repository > Relationship Types
      c_relationship_type TYPE string VALUE 'sap:relatesToBusinessObject'.

    CLASS-METHODS:

      "! Create IF_WEB_HTTP_CLIENT via Communication Arrangement (ABAP Cloud compliant)
      create_http_client
        RETURNING
          VALUE(ro_client) TYPE REF TO if_web_http_client
        RAISING
          zcx_dms_error,

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
          iv_json          TYPE string
          iv_key           TYPE string
        RETURNING
          VALUE(rv_value)  TYPE string.

ENDCLASS.


CLASS zcl_dms_utility IMPLEMENTATION.

  METHOD upload_document.

    DATA(lo_client) = create_http_client( ).

    " CMIS Browser Binding: POST to /browser/{repositoryId}/root
    " with cmisaction=createDocument in multipart body
    DATA(lv_path) = |/browser/{ c_repository_id }/root|.

    DATA: lv_body     TYPE xstring,
          lv_boundary TYPE string.

    build_multipart_body(
      IMPORTING
        iv_file_name = iv_file_name
        iv_mime_type = iv_mime_type
        iv_content   = iv_content
      EXPORTING
        ev_body      = lv_body
        ev_boundary  = lv_boundary ).

    DATA(lo_request) = lo_client->get_http_request( ).
    lo_request->set_uri_path( lv_path ).
    lo_request->set_header_field(
      i_name  = 'Content-Type'
      i_value = |multipart/form-data; boundary={ lv_boundary }| ).
    lo_request->set_binary_data( lv_body ).

    DATA(lo_response) = lo_client->execute( i_method = if_web_http_client=>post ).

    DATA(lv_status)   = lo_response->get_status( )-code.
    DATA(lv_body_str) = lo_response->get_text( ).

    IF lv_status <> 201.
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>api_error
          mv_info = |UPLOAD failed HTTP { lv_status }: { lv_body_str }|.
    ENDIF.

    " Parse objectId and name from CMIS JSON response
    " Response example: {"objectId":"abc-123","name":"invoice.pdf",...}
    rs_result-object_id   = get_json_value( iv_json = lv_body_str iv_key = 'objectId' ).
    rs_result-object_name = get_json_value( iv_json = lv_body_str iv_key = 'name' ).

    lo_client->close( ).

  ENDMETHOD.


  METHOD link_to_business_object.

    DATA(lo_client) = create_http_client( ).

    " CMIS Browser Binding: POST to /browser/{repositoryId}/root
    " with cmisaction=createRelationship to link document to business object
    DATA(lv_path) = |/browser/{ c_repository_id }/root|.

    " Build form-urlencoded body for createRelationship
    " iv_bo_key format depends on DMS configuration — confirm with DMS Admin
    " e.g. for FI Document: "BKPF.<BUKRS>.<BELNR>.<GJAHR>"
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

    DATA(lo_request) = lo_client->get_http_request( ).
    lo_request->set_uri_path( lv_path ).
    lo_request->set_header_field(
      i_name  = 'Content-Type'
      i_value = 'application/x-www-form-urlencoded' ).
    lo_request->set_binary_data( lv_body ).

    DATA(lo_response) = lo_client->execute( i_method = if_web_http_client=>post ).

    DATA(lv_status) = lo_response->get_status( )-code.

    IF lv_status <> 201.
      DATA(lv_resp_body) = lo_response->get_text( ).
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>api_error
          mv_info = |LINK failed HTTP { lv_status }: { lv_resp_body }|.
    ENDIF.

    lo_client->close( ).

  ENDMETHOD.


  METHOD create_http_client.

    TRY.
        " [REPLACE] Communication Arrangement must be created in
        " SAP S/4HANA Cloud: IMG > Communication Management > Communication Arrangements
        " pointing to your BTP DMS service instance
        DATA(lo_destination) = cl_http_destination_provider=>create_by_comm_arrangement(
          comm_scenario = c_comm_scenario ).

        ro_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

      CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
        RAISE EXCEPTION TYPE zcx_dms_error
          EXPORTING
            textid  = zcx_dms_error=>destination_error
            mv_info = |Cannot create HTTP destination: { lx_dest->get_text( ) }|.

      CATCH cx_web_http_client_error INTO DATA(lx_client).
        RAISE EXCEPTION TYPE zcx_dms_error
          EXPORTING
            textid  = zcx_dms_error=>destination_error
            mv_info = |Cannot create HTTP client: { lx_client->get_text( ) }|.
    ENDTRY.

  ENDMETHOD.


  METHOD build_multipart_body.

    " Generate unique boundary using timestamp
    DATA(lv_ts) = cl_abap_context_info=>get_system_date( ) &&
                  cl_abap_context_info=>get_system_time( ).
    ev_boundary = |DMS_BOUNDARY_{ lv_ts }|.

    " Part 1: CMIS properties (JSON) — tells DMS to create a document
    DATA(lv_props_json) =
      |\{"cmis:name":"\{ iv_file_name }",|
      && |"cmis:objectTypeId":"\{ c_object_type_id }"\}|.

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
      && |Content-Disposition: form-data; name="contentfile"; filename="\{ iv_file_name }"\r\n|
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
    DATA(lv_pattern) = |"\{ iv_key }"\\s*:\\s*"([^"]*)"|.

    FIND FIRST OCCURRENCE OF REGEX lv_pattern
      IN iv_json
      SUBMATCHES rv_value.

  ENDMETHOD.

ENDCLASS.
