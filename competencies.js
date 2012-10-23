if (typeof(jQuery) != 'undefined') { (function($) {
  $(document).ready(function() {
    var competency_map     = competencies.competency_map;
    var categories         = competencies.categories;
    var summary_table_path = 'blockquote > table > tbody tr';

    $(summary_table_path).each(function() {
      var last_td = $(this).find('td').last();
      var page    = $(this).find('td > a').text();
      var comps   = new Array();

      $(this).find('td + td').first().removeAttr('width');

      $(competency_map[page]).each(function() {
        comps.push(categories[this]);
      });

      $(last_td).before($('<td />', {text: comps.join(' / ')}));
    });

    $(summary_table_path).first().css('font-weight', 'bold');
  });
})(jQuery)};
