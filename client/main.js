/*
	Stuff!


*/

var paper = Raphael(5, 5, 975, 585);
var paperbg = paper.rect(0, 0, 970, 580);
paperbg.attr({ "fill": "#000", "stroke-width" : 0 });

var statusbutton = paper.rect(820, 490, 140, 80, 10);
statusbutton.attr({"fill" : "#B00"});
statusbutton.click(function () {
	closesocket()
});

var currentzonebg = paper.rect(10, 440, 600, 120, 10);
currentzonebg.attr({ "fill": "#005", "stroke-width" : 0});
var currentzone = paper.text(300, 500, "Current Zone");
currentzone.attr({ "font-size" : 80, "fill" : "#FFF", "test-anchor" : "middle"});

var lapcomparebg = paper.rect(10, 10, 500, 250, 10);
lapcomparebg.attr({ "fill": "#044", "stroke-width" : 0});
var lapcompare = paper.text(260, 135, "±00.0");
lapcompare.attr({ "font-size" : 180, "fill" : "#FFF", "test-anchor" : "middle"});

var laptimebg = paper.rect(10, 270, 500, 160, 10);
laptimebg.attr({ "fill" : "#062", "stroke-width" : 0});
var laptime = paper.text(260, 350, "00:00.0");
laptime.attr({ "font-size" : 120, "fill" : "#FFF", "test-anchor" : "middle"});

var vertbarbg = paper.rect(550, 10, 80, 330, 10);
vertbarbg.attr({ "fill" : "#640", "stroke-width" : 0});
var vertbarbreak = paper.rect(530, 160, 120, 20, 5);
vertbarbreak.attr({ "fill" : "#000", "stroke-width" : 0});
var vertbar = paper.rect(525, 167, 130, 6, 3);
vertbar.attr({ "fill" : "#FFF", "stroke-width" : 0});

var horbarbg = paper.rect(630, 340, 330, 80, 10);
horbarbg.attr({ "fill" : "#640", "stroke-width" : 0});
var horbarbreak = paper.rect(790, 320, 20, 120, 5);
horbarbreak.attr({ "fill" : "#000", "stroke-width" : 0});
var horbar  = paper.rect(797, 315, 6, 130, 5);
horbar.attr({ "fill" : "#FFF", "stroke-width" : 0});


var socket = io.connect('http://' + window.location.host);
socket.on('connect', function () {
	statusbutton.attr({"fill" : "#0B0"});

	socket.on('fifo update', function (data) {
		var updates = data.split("\n");
		for (var i = 0; i < updates.length; i++) {
			var update = updates[i].replace(/\n/g, "").split("/");
			if (update[0] == "laptime") { laptime.attr({ "text" : update[1] }); }
			else if (update[0] == "lapcompare") { lapcompare.attr({ "text" : update[1] }); }
			else if (update[0] == "currentzone") { currentzone.attr({ "text" : update[1] }); }
			else if (update[0] == "accelx") {
				var adjustment = Math.round( 797 - (update[1] * 165) );
				horbar.animate( { "x" : adjustment }, 100);
			}
			else if (update[0] == "accely") {
				var adjustment = Math.round( 167 + (update[1] * 165) );
				vertbar.animate( { "y" : adjustment }, 100);
			}
		}
	});
});

function closesocket() {
	socket.disconnect();
	statusbutton.attr({"fill" : "#B00"});
}

