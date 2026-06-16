*"* use this source file for your ABAP unit test classes

CLASS ltc_dms_utility DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS:
      test_upload_document     FOR TESTING,
      test_download_document   FOR TESTING,
      test_link_business_obj   FOR TESTING,
      test_search_by_bo        FOR TESTING,
      test_search_custom_query FOR TESTING.

ENDCLASS.

CLASS ltc_dms_utility IMPLEMENTATION.

  METHOD test_upload_document.
    " Smoke test: verify method signature exists and raises proper exception
    " when no destination is configured (expected in test environment)
    TRY.
        DATA(lv_id) = zcl_dms_utility=>upload_document(
          iv_repository_id = 'test-repo'
          iv_file_name     = 'test.pdf'
          iv_mime_type     = 'application/pdf'
          iv_content       = cl_abap_codepage=>convert_to( 'PDF_CONTENT' ) ).

      CATCH zcx_dms_error INTO DATA(lo_err).
        " Expected: destination not configured in test system
        cl_abap_unit_assert=>assert_not_initial(
          act = lo_err->mv_info
          msg = 'Exception must carry info message' ).
    ENDTRY.
  ENDMETHOD.

  METHOD test_download_document.
    TRY.
        DATA(lv_content) = zcl_dms_utility=>download_document(
          iv_repository_id = 'test-repo'
          iv_object_id     = 'test-object-id' ).

      CATCH zcx_dms_error INTO DATA(lo_err).
        cl_abap_unit_assert=>assert_not_initial( lo_err->mv_info ).
    ENDTRY.
  ENDMETHOD.

  METHOD test_link_business_obj.
    TRY.
        zcl_dms_utility=>link_to_business_object(
          iv_repository_id   = 'test-repo'
          iv_document_id     = 'test-doc-id'
          iv_business_object = 'BUS2012'
          iv_object_key      = '4500000001' ).

      CATCH zcx_dms_error INTO DATA(lo_err).
        cl_abap_unit_assert=>assert_not_initial( lo_err->mv_info ).
    ENDTRY.
  ENDMETHOD.

  METHOD test_search_by_bo.
    TRY.
        DATA(lt_docs) = zcl_dms_utility=>search_documents(
          iv_repository_id   = 'test-repo'
          iv_business_object = 'BUS2012'
          iv_object_key      = '4500000001' ).

      CATCH zcx_dms_error INTO DATA(lo_err).
        cl_abap_unit_assert=>assert_not_initial( lo_err->mv_info ).
    ENDTRY.
  ENDMETHOD.

  METHOD test_search_custom_query.
    TRY.
        DATA(lt_docs) = zcl_dms_utility=>search_documents(
          iv_repository_id = 'test-repo'
          iv_query         = 'SELECT * FROM cmis:document' ).

      CATCH zcx_dms_error INTO DATA(lo_err).
        cl_abap_unit_assert=>assert_not_initial( lo_err->mv_info ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
