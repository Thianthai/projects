CLASS zcl_dms_utility DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_document,
        object_id   TYPE string,
        name        TYPE string,
        mime_type   TYPE string,
        size        TYPE i,
        created_at  TYPE string,
        modified_at TYPE string,
      END OF ty_document,
      tt_documents TYPE STANDARD TABLE OF ty_document WITH EMPTY KEY,

      BEGIN OF ty_link,
        document_id     TYPE string,
        business_object TYPE string,
        object_key      TYPE string,
      END OF ty_link.

    CLASS-METHODS:
      "! Upload a document to DMS repository
      "! @parameter iv_repository_id | DMS Repository ID
      "! @parameter iv_file_name     | File name with extension
      "! @parameter iv_mime_type     | MIME type (e.g. application/pdf)
      "! @parameter iv_content       | File content as xstring
      "! @parameter rv_object_id     | Returned DMS Object ID
      upload_document
        IMPORTING
          iv_repository_id TYPE string
          iv_file_name     TYPE string
          iv_mime_type     TYPE string
          iv_content       TYPE xstring
        RETURNING
          VALUE(rv_object_id) TYPE string
        RAISING
          zcx_dms_error,

      "! Download a document from DMS
      "! @parameter iv_repository_id | DMS Repository ID
      "! @parameter iv_object_id     | DMS Object ID
      "! @parameter rv_content       | File content as xstring
      download_document
        IMPORTING
          iv_repository_id TYPE string
          iv_object_id     TYPE string
        RETURNING
          VALUE(rv_content) TYPE xstring
        RAISING
          zcx_dms_error,

      "! Link a DMS document to a business object
      "! @parameter iv_repository_id  | DMS Repository ID
      "! @parameter iv_document_id    | DMS Document ID
      "! @parameter iv_business_object| Business Object type (e.g. 'BUS2012' for PO)
      "! @parameter iv_object_key     | Business Object key
      link_to_business_object
        IMPORTING
          iv_repository_id   TYPE string
          iv_document_id     TYPE string
          iv_business_object TYPE string
          iv_object_key      TYPE string
        RAISING
          zcx_dms_error,

      "! Search documents in DMS repository
      "! @parameter iv_repository_id | DMS Repository ID
      "! @parameter iv_query         | CMIS query string (optional)
      "! @parameter iv_business_object | Filter by business object type (optional)
      "! @parameter iv_object_key    | Filter by business object key (optional)
      "! @parameter rt_documents     | List of matching documents
      search_documents
        IMPORTING
          iv_repository_id   TYPE string
          iv_query           TYPE string   OPTIONAL
          iv_business_object TYPE string   OPTIONAL
          iv_object_key      TYPE string   OPTIONAL
        RETURNING
          VALUE(rt_documents) TYPE tt_documents
        RAISING
          zcx_dms_error.

  PRIVATE SECTION.

    CONSTANTS:
      c_destination   TYPE rfcdest VALUE 'DMS_BTP',       " SM59 HTTP Destination
      c_api_path_base TYPE string  VALUE '/browser'.

    CLASS-METHODS:
      "! Create and configure HTTP client using SM59 destination
      create_http_client
        RETURNING
          VALUE(ro_client) TYPE REF TO if_http_client
        RAISING
          zcx_dms_error,

      "! Send HTTP request and return parsed JSON response
      send_request
        IMPORTING
          io_client       TYPE REF TO if_http_client
          iv_method       TYPE string
          iv_path         TYPE string
          iv_body         TYPE xstring OPTIONAL
          iv_content_type TYPE string  OPTIONAL
        RETURNING
          VALUE(rv_response) TYPE string
        RAISING
          zcx_dms_error,

      "! Parse HTTP error response and raise exception
      handle_http_error
        IMPORTING
          iv_status_code TYPE i
          iv_response    TYPE string
        RAISING
          zcx_dms_error,

      "! Build multipart/form-data body for file upload
      build_multipart_body
        IMPORTING
          iv_file_name    TYPE string
          iv_mime_type    TYPE string
          iv_content      TYPE xstring
          iv_object_type  TYPE string DEFAULT 'cmis:document'
        EXPORTING
          ev_body         TYPE xstring
          ev_content_type TYPE string.

ENDCLASS.


CLASS zcl_dms_utility IMPLEMENTATION.

  METHOD upload_document.
    DATA: lo_client       TYPE REF TO if_http_client,
          lv_path         TYPE string,
          lv_body         TYPE xstring,
          lv_content_type TYPE string,
          lv_response     TYPE string,
          lo_json         TYPE REF TO /ui2/cl_json.

    lo_client = create_http_client( ).

    lv_path = |{ c_api_path_base }/{ iv_repository_id }/root|.

    build_multipart_body(
      IMPORTING
        iv_file_name    = iv_file_name
        iv_mime_type    = iv_mime_type
        iv_content      = iv_content
      EXPORTING
        ev_body         = lv_body
        ev_content_type = lv_content_type ).

    lv_response = send_request(
      io_client       = lo_client
      iv_method       = 'POST'
      iv_path         = lv_path
      iv_body         = lv_body
      iv_content_type = lv_content_type ).

    " Extract objectId from JSON response
    DATA(lo_result) = /ui2/cl_json=>parse( lv_response ).
    rv_object_id = lo_result->get_string( '$.objectId' ).

    lo_client->close( ).

  ENDMETHOD.


  METHOD download_document.
    DATA: lo_client   TYPE REF TO if_http_client,
          lv_path     TYPE string,
          lv_response TYPE string.

    lo_client = create_http_client( ).

    lv_path = |{ c_api_path_base }/{ iv_repository_id }/root|
           && |?objectId={ iv_object_id }&cmisselector=content|.

    " For binary content, get raw bytes from response
    lo_client->request->set_header_field(
      name  = '~request_method'
      value = 'GET' ).
    lo_client->request->set_header_field(
      name  = '~request_uri'
      value = lv_path ).

    lo_client->send( EXCEPTIONS OTHERS = 1 ).
    lo_client->receive( EXCEPTIONS OTHERS = 1 ).

    DATA(lv_status) = lo_client->response->get_status_code( ).
    IF lv_status <> 200.
      lv_response = lo_client->response->get_cdata( ).
      handle_http_error( iv_status_code = lv_status iv_response = lv_response ).
    ENDIF.

    rv_content = lo_client->response->get_data( ).
    lo_client->close( ).

  ENDMETHOD.


  METHOD link_to_business_object.
    DATA: lo_client   TYPE REF TO if_http_client,
          lv_path     TYPE string,
          lv_json     TYPE string,
          lv_body     TYPE xstring.

    lo_client = create_http_client( ).

    lv_path = |/sdm/v1/repositories/{ iv_repository_id }|
           && |/documents/{ iv_document_id }/links|.

    lv_json = |\{"businessObject":"\{ iv_business_object }",|
           && |"objectKey":"\{ iv_object_key }"\}|.

    lv_body = cl_abap_codepage=>convert_to( lv_json ).

    send_request(
      io_client       = lo_client
      iv_method       = 'POST'
      iv_path         = lv_path
      iv_body         = lv_body
      iv_content_type = 'application/json' ).

    lo_client->close( ).

  ENDMETHOD.


  METHOD search_documents.
    DATA: lo_client    TYPE REF TO if_http_client,
          lv_path      TYPE string,
          lv_query_str TYPE string,
          lv_response  TYPE string.

    lo_client = create_http_client( ).

    IF iv_query IS NOT INITIAL.
      lv_query_str = iv_query.
    ELSEIF iv_business_object IS NOT INITIAL AND iv_object_key IS NOT INITIAL.
      lv_query_str = |SELECT * FROM cmis:document WHERE |
                  && |sap:bo = '\{ iv_business_object }' AND |
                  && |sap:bokey = '\{ iv_object_key }'|.
    ELSE.
      lv_query_str = 'SELECT * FROM cmis:document'.
    ENDIF.

    " URL-encode the query
    DATA(lv_encoded_query) = cl_http_utility=>escape_url( lv_query_str ).

    lv_path = |{ c_api_path_base }/{ iv_repository_id }/root|
           && |?cmisselector=query&q={ lv_encoded_query }|.

    lv_response = send_request(
      io_client = lo_client
      iv_method = 'GET'
      iv_path   = lv_path ).

    " Parse JSON array into result table
    DATA(lo_json_array) = /ui2/cl_json=>parse( lv_response ).
    DATA(lo_results)    = lo_json_array->get( '$.results' ).

    IF lo_results IS BOUND.
      DATA(lv_count) = lo_results->get_count( ).
      DATA(lv_idx)   = 0.
      WHILE lv_idx < lv_count.
        DATA(lo_item) = lo_results->get_item( lv_idx ).
        DATA ls_doc TYPE ty_document.
        ls_doc-object_id   = lo_item->get_string( '$.objectId' ).
        ls_doc-name        = lo_item->get_string( '$.name' ).
        ls_doc-mime_type   = lo_item->get_string( '$.contentStreamMimeType' ).
        ls_doc-created_at  = lo_item->get_string( '$.creationDate' ).
        ls_doc-modified_at = lo_item->get_string( '$.lastModificationDate' ).
        APPEND ls_doc TO rt_documents.
        lv_idx = lv_idx + 1.
      ENDWHILE.
    ENDIF.

    lo_client->close( ).

  ENDMETHOD.


  METHOD create_http_client.
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
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>destination_error
          mv_info = |Cannot create HTTP client for destination: { c_destination }|.
    ENDIF.

  ENDMETHOD.


  METHOD send_request.
    io_client->request->set_header_field(
      name  = '~request_method'
      value = iv_method ).
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

    io_client->send( EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>send_error
          mv_info = |HTTP send failed for { iv_method } { iv_path }|.
    ENDIF.

    io_client->receive( EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_dms_error
        EXPORTING
          textid  = zcx_dms_error=>receive_error
          mv_info = |HTTP receive failed for { iv_method } { iv_path }|.
    ENDIF.

    DATA(lv_status) = io_client->response->get_status_code( ).
    rv_response     = io_client->response->get_cdata( ).

    IF lv_status >= 400.
      handle_http_error(
        iv_status_code = lv_status
        iv_response    = rv_response ).
    ENDIF.

  ENDMETHOD.


  METHOD handle_http_error.
    DATA(lv_msg) = |HTTP { iv_status_code }: { iv_response }|.

    CASE iv_status_code.
      WHEN 401 OR 403.
        RAISE EXCEPTION TYPE zcx_dms_error
          EXPORTING
            textid  = zcx_dms_error=>auth_error
            mv_info = lv_msg.
      WHEN 404.
        RAISE EXCEPTION TYPE zcx_dms_error
          EXPORTING
            textid  = zcx_dms_error=>not_found
            mv_info = lv_msg.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_dms_error
          EXPORTING
            textid  = zcx_dms_error=>api_error
            mv_info = lv_msg.
    ENDCASE.

  ENDMETHOD.


  METHOD build_multipart_body.
    " Generate unique boundary
    DATA(lv_boundary) = |----FormBoundary{ sy-timlo }{ sy-datum }|.
    ev_content_type = |multipart/form-data; boundary={ lv_boundary }|.

    " Part 1: document metadata (JSON)
    DATA(lv_meta_json) = |\{"cmis:name":"\{ iv_file_name }",|
                       && |"cmis:objectTypeId":"\{ iv_object_type }"\}|.

    DATA(lv_body_str) TYPE string.
    lv_body_str = |--{ lv_boundary }\r\n|
               && |Content-Disposition: form-data; name="propertyValues"\r\n|
               && |Content-Type: application/json;charset=utf-8\r\n\r\n|
               && |{ lv_meta_json }\r\n|
               && |--{ lv_boundary }\r\n|
               && |Content-Disposition: form-data; name="contentfile"; filename="\{ iv_file_name }"\r\n|
               && |Content-Type: { iv_mime_type }\r\n\r\n|.

    " Convert text prefix to xstring then append binary content then closing boundary
    DATA(lv_prefix) = cl_abap_codepage=>convert_to( lv_body_str ).
    DATA(lv_suffix) = cl_abap_codepage=>convert_to( |\r\n--{ lv_boundary }--\r\n| ).

    ev_body = lv_prefix && iv_content && lv_suffix.

  ENDMETHOD.

ENDCLASS.
