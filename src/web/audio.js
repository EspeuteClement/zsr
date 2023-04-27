



class MyAudioProcessor extends AudioWorkletProcessor {
	
	
	constructor(...args) {
		super(...args);

		this.gen_samples = null;
		this.memory = new WebAssembly.Memory({initial:100});
		this.playSound = null;
		var self = this;

		var mem = this.memory;
		console.log(mem);

		var port = this.port;

		function print(offset, length) {
			var bytes = new Uint8Array(mem.buffer, offset, length);
			var copy = new ArrayBuffer(bytes.byteLength);
			new Uint8Array(copy).set(bytes);
			port.postMessage(copy, [copy]);
		}

		this.port.onmessage = (e) => {

			var importObject = {
				env: {
					memory: this.memory,
					print: print,
				}
			};

			var buffer = e.data;

			self.port.onmessage = (e) => {
				if (self.playSound != null) {
					self.playSound(e.data);
				} else {
					console.log("Cant play sound");
				}
			};

			WebAssembly.instantiate(buffer, importObject).then(
				obj => {
					obj.instance.exports.init(sampleRate);
					this.gen_samples = obj.instance.exports.gen_samples;
					self.playSound = obj.instance.exports.playSound;
					console.log(obj.instance.exports);
				}
			);
		}
	}




	process(inputList, outputList, parameters) {

		if (this.gen_samples !== null && outputList.length > 0) {
			var numSamples = outputList[0][0].length;
			var addrs = this.gen_samples(numSamples);
			var buffer = this.memory.buffer.slice(addrs, addrs + numSamples * 2 * 4);
			var samples = new Float32Array(buffer);

			//console.log(samples);

			for (let output = 0; output < outputList.length; output++) {
				for (let channel = 0; channel < outputList[output].length; channel++) {
					for (let sample = 0; sample < outputList[output][channel].length; sample++) {
						outputList[output][channel][sample] = samples[sample*2 + channel];
					}
				}
			}
		}

		return true;
	}
}

registerProcessor("my-audio-processor", MyAudioProcessor);


