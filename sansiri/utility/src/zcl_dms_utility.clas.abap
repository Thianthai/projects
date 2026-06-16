CLASS zcl_dms_utility DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_upload_result,
        object_id   TYPE string,  " DMS Object ID ของไฟล์ที่ถูกอัปโหลด
        object_name TYPE string,
      END OF ty_upload_result,

      BEGIN OF ty_smartform_params,
        control_parameters TYPE ssfctrlop,   " ส่งให้ SmartForm FM: CONTROL_PARAMETERS
        output_options     TYPE ssfcompop,   " ส่งให้ SmartForm FM: OUTPUT_OPTIONS
      END OF ty_smartform_params.

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
          zcx_dms_error,

      "! [Standard ABAP — not ABAP Cloud compliant due to SSF/spool APIs]
      "! Return pre-configured SSF parameters for silent spool output (no physical print).
      "! Caller must pass these to the SmartForm function module call,
      "! then pass the returned spool ID to upload_smartform_to_dms().
      "! @parameter rs_params | SSF control_parameters + output_options ready to use
      prepare_smartform_params
        RETURNING
          VALUE(rs_params) TYPE ty_smartform_params,

      "! [Standard ABAP — not ABAP Cloud compliant due to SSF/spool APIs]
      "! Convert a SmartForm spool job to PDF and upload it to DMS.
      "! Typical usage:
      "!   1. Call prepare_smartform_params() to get SSF params
      "!   2. Call SSF_FUNCTION_MODULE_NAME to get FM name
      "!   3. Call the SmartForm FM with the SSF params — get back spool_job_id
      "!   4. Call this method with the spool_job_id and desired filename
      "! @parameter iv_spool_job_id | Spool request number returned by SmartForm FM
      "! @parameter iv_file_name    | Desired filename in DMS e.g. payment_slip.pdf
      "! @parameter rs_result       | Upload result containing DMS Object ID
      upload_smartform_to_dms
        IMPORTING
          iv_spool_job_id  TYPE rqident
          iv_file_name     TYPE string
        RETURNING
          VALUE(rs_result) TYPE ty_upload_result
        RAISING
          zcx_dms_error,

      "! [Standard ABAP — not ABAP Cloud compliant due to SSF/spool APIs]
      "! Full end-to-end: render SmartForm to PDF silently, upload to DMS,
      "! and link the result to a SAP business object in one call.
      "! Step 1 — prepare SSF params
      "! Step 2 — get SmartForm FM name
      "! Step 3 — caller runs SmartForm FM with their own data (see comment inside)
      "! Step 4 — convert spool to PDF and upload to DMS
      "! Step 5 — link DMS document to business object
      "! @parameter iv_formname    | SmartForm name e.g. ZSMARTFORM_PAYMENT
      "! @parameter iv_file_name   | Filename for DMS e.g. payment_slip.pdf
      "! @parameter iv_bo_type     | Business Object type e.g. BKPF, BUS2012
      "! @parameter iv_bo_key      | Business Object key e.g. 0001.1800000001.2025
      "! @parameter rs_result      | Upload result containing DMS Object ID
      attach_smartform_to_bo
        IMPORTING
          iv_formname      TYPE tdsfname
          iv_file_name     TYPE string
          iv_bo_type       TYPE string
          iv_bo_key        TYPE string
        RETURNING
          VALUE(rs_result) TYPE ty_upload_result
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
      c_relationship_type TYPE string VALUE 'sap:relatesToBusinessObject',

      "! [REPLACE] Spool output device for SmartForm — must exist in SPAD
      "!           Use a non-physical device to avoid accidental printing
      c_spool_device      TYPE tdprnter VALUE 'LOCL'.

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

      "! [Standard ABAP] Convert spool request to PDF xstring
      "! Uses CONVERT_ABAPSPOOLJOB_2_PDF — not released for ABAP Cloud Development
      convert_spool_to_xstring
        IMPORTING
          iv_spool_job_id  TYPE rqident
        RETURNING
          VALUE(rv_pdf)    TYPE xstring
        RAISING
          zcx_dms_error,

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


  METHOD prepare_smartform_params.

    " Configure SSF control parameters for silent output (no dialog, no preview)
    rs_params-control_parameters-no_dialog = abap_true.
    rs_params-control_parameters-preview   = abap_false.
    " GETOTF = false → output goes to spool, not OTF table
    rs_params-control_parameters-getotf    = abap_false.

    " Configure output options — route to spool only, no physical print
    " [REPLACE] c_spool_device: confirm with BASIS which spool device to use
    rs_params-output_options-tddest    = c_spool_device.
    rs_params-output_options-tdnoprev  = abap_true.   " no preview dialog
    rs_params-output_options-tdnoprint = abap_true.   " create spool but do NOT send to printer

  ENDMETHOD.


  METHOD upload_smartform_to_dms.

    " Step 1: Convert spool job to PDF xstring
    DATA(lv_pdf) = convert_spool_to_xstring( iv_spool_job_id ).

    " Step 2: Upload PDF to DMS (reuse existing method)
    rs_result = upload_document(
      iv_file_name = iv_file_name
      iv_mime_type = 'application/pdf'
      iv_content   = lv_pdf ).

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


  METHOD attach_smartform_to_bo.

    " ----------------------------------------------------------------
    " Step 1: Get SSF parameters configured for silent spool output
    " ----------------------------------------------------------------
    DATA(ls_params) = prepare_smartform_params( ).

    " ----------------------------------------------------------------
    " Step 2: Resolve SmartForm name to its generated function module
    " ----------------------------------------------------------------
    DATA lv_fm_name TYPE rs38l_fnam.

    CALL FUNCTION 'SSF_FUNCTION_MODULE_NAME'
      EXPORTING
        formname           = iv_formname
      IMPORTING
        fm_name            = lv_fm_name
      EXCEPTIONS
        no_form            = 1
        no_function_module = 2
        OTHERS             = 3.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>api_error
          mv_info = |SmartForm '{ iv_formname }' not found or has no function module|.
    ENDIF.

    " ----------------------------------------------------------------
    " Step 3: Call SmartForm FM — insert form-specific data here
    " [REPLACE] Replace the EXPORTING/TABLES parameters below with
    "           the actual import parameters of your SmartForm.
    "           Keep CONTROL_PARAMETERS and OUTPUT_OPTIONS as-is.
    " ----------------------------------------------------------------
    DATA ls_job_output TYPE ssfoutput_optline.

    CALL FUNCTION lv_fm_name
      EXPORTING
        control_parameters = ls_params-control_parameters
        output_options     = ls_params-output_options
*       user_settings      = abap_false          " usually keep false for background
*       <your_form_param>  = <your_data>         " [REPLACE] form-specific data
      IMPORTING
        job_output_options = ls_job_output
      EXCEPTIONS
        formatting_error   = 1
        internal_error     = 2
        send_error         = 3
        user_canceled      = 4
        OTHERS             = 5.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>api_error
          mv_info = |SmartForm '{ iv_formname }' execution failed (subrc={ sy-subrc })|.
    ENDIF.

    " ----------------------------------------------------------------
    " Step 4: Convert spool output to PDF and upload to DMS
    " Spool request ID is returned in job_output_options after FM call
    " ----------------------------------------------------------------
    rs_result = upload_smartform_to_dms(
      iv_spool_job_id = ls_job_output-spool_id    " [REPLACE] confirm field name with SSF output structure
      iv_file_name    = iv_file_name ).

    " ----------------------------------------------------------------
    " Step 5: Link uploaded document to the business object
    " ----------------------------------------------------------------
    link_to_business_object(
      iv_object_id = rs_result-object_id
      iv_bo_type   = iv_bo_type
      iv_bo_key    = iv_bo_key ).

  ENDMETHOD.


  METHOD convert_spool_to_xstring.

    " CONVERT_ABAPSPOOLJOB_2_PDF is Standard ABAP only — not released for ABAP Cloud
    " Returns PDF as table of 255-byte lines (type pdf_lines)
    TYPES: tt_pdf TYPE STANDARD TABLE OF tline WITH EMPTY KEY.
    DATA: lt_pdf     TYPE tt_pdf,
          lv_pdf_len TYPE i.

    CALL FUNCTION 'CONVERT_ABAPSPOOLJOB_2_PDF'
      EXPORTING
        src_spoolid          = iv_spool_job_id
        no_dialog            = abap_true
        dst_device           = c_spool_device  " [REPLACE] same device used in prepare_smartform_params
      IMPORTING
        pdf_bytecount        = lv_pdf_len
      TABLES
        pdf                  = lt_pdf
      EXCEPTIONS
        err_no_abap_spooljob = 1
        err_no_spooljob      = 2
        err_no_permission    = 3
        err_conv_not_possible = 4
        err_bad_dstdevice    = 5
        user_cancelled       = 6
        err_spoolerror       = 7
        OTHERS               = 8.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>api_error
          mv_info = |Spool to PDF conversion failed (subrc={ sy-subrc }) for spool { iv_spool_job_id }|.
    ENDIF.

    " Concatenate all PDF line entries into a single xstring
    LOOP AT lt_pdf INTO DATA(lv_line).
      rv_pdf = rv_pdf && cl_abap_codepage=>convert_to(
        source   = lv_line
        codepage = 'UTF-8' ).
    ENDLOOP.

    " Trim to actual PDF byte length to remove padding from last line
    rv_pdf = rv_pdf(lv_pdf_len).

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
