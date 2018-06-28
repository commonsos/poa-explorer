import $ from 'jquery'
import UJS from 'phoenix_ujs'

"use strict";

(function() {
  function query_function (element) {
    let response_container = $(element).parents("[data-function]:eq(0)").find("[data-function-response]:eq(0)");

    let form = $(element).parents("[data-form-read-contract]:eq(0)");

    let url = $(form).data("url");

    let function_name = $(form).find("input[name=function_name]:eq(0)").val();

    let input_values = $.map($(form).find("input[name=function_input]"), function(element) {
      let value = $(element).val();

      let number = parseInt(value);

      return number == NaN ? value : number
    });

    UJS.xhr(url, "POST", {
      type: 'json',
      data: {function_name: function_name, args: input_values},
      success: function(xhr) {
        $(response_container).html(xhr.response);
      }
    });
  };

  function initialize(){
    $("[data-query-button]").on("click", function(click){
      query_function($(this));

      event.stopPropagation();
      event.preventDefault();
    });
  };

  initialize();
})();
