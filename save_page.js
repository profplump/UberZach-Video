//phantomjs save_page.js 'http://extratorrent.cc/search/?search=grand+tour+s01e06&new=1&x=0&y=0'

var system = require('system');
var page = require('webpage').create();

page.open(system.args[1], function()
{
    console.log(page.content);
    phantom.exit();
});
