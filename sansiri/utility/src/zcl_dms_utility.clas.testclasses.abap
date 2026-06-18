*"* use this source file for your ABAP unit test classes

* =============================================================================
* Test class: Attach SmartForm to Business Object via DMS
* [Standard ABAP — not ABAP Cloud compliant due to SSF/spool APIs]
*
* Demonstrates the full end-to-end flow:
*   1. Prepare SSF parameters for silent spool output
*   2. Resolve SmartForm name to function module
*   3. Call SmartForm FM (no physical print)
*   4. Convert spool to PDF xstring
*   5. Upload PDF to DMS
*   6. Link DMS document to SAP business object
* =============================================================================
CLASS ltc_smartform_attach DEFINITION FINAL FOR TESTING
  DURATION MEDIUM
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.

    " ---------------------------------------------------------------
    " HARD-CODED test values — Replace before running in real system
    " ---------------------------------------------------------------
    CONSTANTS:
      "! [REPLACE] SmartForm name to test
      c_formname    TYPE tdsfname VALUE 'ZSMARTFORM_PAYMENT',

      "! [REPLACE] Desired filename in DMS
      c_file_name   TYPE string   VALUE 'payment_slip.pdf',

      "! [REPLACE] Business Object type for the link
      c_bo_type     TYPE string   VALUE 'BKPF',

      "! [REPLACE] Business Object key — confirm format with DMS Admin
      "!           e.g. BKPF key format: "<BUKRS>.<BELNR>.<GJAHR>"
      c_bo_key      TYPE string   VALUE '0001.1800000001.2025',

      "! [REPLACE] Spool output device — must exist in SPAD, non-physical printer
      c_spool_device TYPE tdprnter VALUE 'LOCL'.

    METHODS:
      "! Full flow: SmartForm → spool → PDF → DMS → link to BO
      test_attach_smartform_to_fi_doc FOR TESTING.

    METHODS:
      "! Configure SSF parameters for silent spool output (no physical print)
      prepare_smartform_params
        RETURNING
          VALUE(rs_ctrl) TYPE ssfctrlop
          VALUE(rs_outp) TYPE ssfcompop,   " not valid syntax — see implementation

      "! Convert spool request number to PDF xstring
      convert_spool_to_xstring
        IMPORTING
          iv_spool_job_id TYPE rqident
        RETURNING
          VALUE(rv_pdf)   TYPE xstring
        RAISING
          zcx_dms_error.

ENDCLASS.


CLASS ltc_smartform_attach IMPLEMENTATION.

  METHOD test_attach_smartform_to_fi_doc.

    " ----------------------------------------------------------------
    " Step 1: Configure SSF params for silent spool output
    " ----------------------------------------------------------------
    DATA ls_ctrl TYPE ssfctrlop.
    DATA ls_outp TYPE ssfcompop.

    ls_ctrl-no_dialog = abap_true.
    ls_ctrl-preview   = abap_false.
    ls_ctrl-getotf    = abap_false.   " output to spool, not OTF table

    " [REPLACE] c_spool_device: non-physical printer device in SPAD
    ls_outp-tddest    = c_spool_device.
    ls_outp-tdnoprev  = abap_true.    " no preview dialog
    ls_outp-tdnoprint = abap_true.    " create spool entry but do NOT send to printer

    " ----------------------------------------------------------------
    " Step 2: Resolve SmartForm name to its generated function module
    " ----------------------------------------------------------------
    DATA lv_fm_name TYPE rs38l_fnam.

    CALL FUNCTION 'SSF_FUNCTION_MODULE_NAME'
      EXPORTING
        formname           = c_formname
      IMPORTING
        fm_name            = lv_fm_name
      EXCEPTIONS
        no_form            = 1
        no_function_module = 2
        OTHERS             = 3.

    cl_abap_unit_assert=>assert_subrc(
      act = sy-subrc
      exp = 0
      msg = |SmartForm '{ c_formname }' not found| ).

    " ----------------------------------------------------------------
    " Step 3: Call SmartForm FM — output goes to spool only
    " [REPLACE] Add form-specific EXPORTING/TABLES parameters below
    "           to pass the actual business document data to the form
    " ----------------------------------------------------------------
    DATA ls_job_output TYPE ssfoutput_optline.

    CALL FUNCTION lv_fm_name
      EXPORTING
        control_parameters = ls_ctrl
        output_options     = ls_outp
*       user_settings      = abap_false
*       <your_form_param>  = <your_data>     " [REPLACE] form-specific data
      IMPORTING
        job_output_options = ls_job_output
      EXCEPTIONS
        formatting_error   = 1
        internal_error     = 2
        send_error         = 3
        user_canceled      = 4
        OTHERS             = 5.

    cl_abap_unit_assert=>assert_subrc(
      act = sy-subrc
      exp = 0
      msg = |SmartForm '{ c_formname }' execution failed| ).

    " ----------------------------------------------------------------
    " Step 4: Convert spool to PDF xstring
    " [REPLACE] Confirm spool_id field name from ls_job_output in SE11
    " ----------------------------------------------------------------
    DATA(lv_pdf) = convert_spool_to_xstring(
      iv_spool_job_id = ls_job_output-spool_id ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_pdf
      msg = 'PDF xstring must not be empty after spool conversion' ).

    " ----------------------------------------------------------------
    " Step 5: Upload PDF to DMS
    " ----------------------------------------------------------------
    DATA(ls_result) = zcl_dms_utility=>upload_document(
      iv_file_name = c_file_name
      iv_mime_type = 'application/pdf'
      iv_content   = lv_pdf ).

    cl_abap_unit_assert=>assert_not_initial(
      act = ls_result-object_id
      msg = 'DMS object_id must be returned after upload' ).

    " ----------------------------------------------------------------
    " Step 6: Link uploaded document to SAP business object
    " ----------------------------------------------------------------
    zcl_dms_utility=>link_to_business_object(
      iv_object_id = ls_result-object_id
      iv_bo_type   = c_bo_type
      iv_bo_key    = c_bo_key ).

  ENDMETHOD.


  METHOD convert_spool_to_xstring.

    " CONVERT_ABAPSPOOLJOB_2_PDF is Standard ABAP only
    " Returns PDF as table of 255-byte lines (type pdf_lines)
    TYPES tt_pdf TYPE STANDARD TABLE OF tline WITH EMPTY KEY.
    DATA: lt_pdf     TYPE tt_pdf,
          lv_pdf_len TYPE i.

    CALL FUNCTION 'CONVERT_ABAPSPOOLJOB_2_PDF'
      EXPORTING
        src_spoolid           = iv_spool_job_id
        no_dialog             = abap_true
        dst_device            = c_spool_device   " [REPLACE] same device as prepare step
      IMPORTING
        pdf_bytecount         = lv_pdf_len
      TABLES
        pdf                   = lt_pdf
      EXCEPTIONS
        err_no_abap_spooljob  = 1
        err_no_spooljob       = 2
        err_no_permission     = 3
        err_conv_not_possible = 4
        err_bad_dstdevice     = 5
        user_cancelled        = 6
        err_spoolerror        = 7
        OTHERS                = 8.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>api_error
          mv_info = |Spool to PDF failed (subrc={ sy-subrc }) for spool { iv_spool_job_id }|.
    ENDIF.

    " Concatenate all PDF lines into xstring then trim to actual byte length
    LOOP AT lt_pdf INTO DATA(lv_line).
      rv_pdf = rv_pdf && cl_abap_codepage=>convert_to(
        source   = lv_line
        codepage = 'UTF-8' ).
    ENDLOOP.

    rv_pdf = rv_pdf(lv_pdf_len).

  ENDMETHOD.

  METHOD prepare_smartform_params. "#EC NEEDED
    " Unused — logic is inlined inside test_attach_smartform_to_fi_doc
    " for readability of the step-by-step flow
  ENDMETHOD.

ENDCLASS.
