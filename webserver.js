var app = require('http').createServer(handler)
	, io = require('socket.io').listen(app)
	, fs = require('fs')
	, url = require('url')

app.listen(8000);
var fifoStream = fs.createReadStream('./var/sensorgrabber.fifo');
fifoStream.setEncoding('utf8');
console.log('[1;32mPipe opened[0m');

function handler (req, res) {
	var pathname = url.parse(req.url).pathname;

	if (pathname.match(/\.js$/)) {
		fs.readFile(__dirname + pathname, function (err, data) {
			if (err) {
				res.writeHead(500);
				return res.end('Error loading ' + pathname);
			}
	
			res.writeHead(200);
			res.end(data);
		});
	}
	else {
		fs.readFile(__dirname + "/client/default.html", function (err, data) {
			res.writeHead(200);
			res.end(data);
		});
	}
}

io.sockets.on('connection', function (socket) {
	console.log("[1;34mNew socket[0m");
	socket.on('confirmation', function (data) {
		console.log("[1;33mSocket confirmed: " + data + "[0m");
	});

	fifoStream.on('end', function() {
		// Reopen it!
		fifoStream.destroy();
		console.log('[1;32mPipe died[0m');
	});

	fifoStream.on('data', function (data) {
		console.log('[1;32mFIFO update: [0m' + data.toString());
		socket.emit('fifo update', '' + data.toString());
	});

/*
	socket.on('turnon', function (data) {
		if (data == "*") {
			for (var z=0; z<16; z++) { led[z] = true; }
		}
		else if (data >= 0) {
			led[data] = true;
		}
		console.log("[1;33mUpdate from client: turn on " + data);
		socket.broadcast.emit('ledupdate', { num: data, state: true });
		iocmdpipe.write(data + ",1\n");
		console.log("[1;34mDispatched ON update to clients for led " + data);
	});

	socket.on('turnoff', function (data) {
		if (data == "*") {
			for (var z=0; z<16; z++) { led[z] = false; }
		}
		else if (data >= 0) {
			led[data] = false;
		}
		console.log("[1;33mUpdate from client: turn off " + data);
		socket.broadcast.emit('ledupdate', { num: data, state: false });
		iocmdpipe.write(data + ",0\n");
		console.log("[1;34mDispatched OFF update to clients for led " + data);
	});
*/

});

