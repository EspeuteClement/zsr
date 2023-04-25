
class MyAudioProcessor extends AudioWorkletProcessor {
	
	
	constructor(...args) {
		super(...args);

		this.gen_samples = null;
		this.memory = new WebAssembly.Memory({initial:100});

		this.port.onmessage = (e) => {

			var importObject = {
				env: {
					memory: this.memory,
				}
			};

			var buffer = e.data;

			WebAssembly.instantiate(buffer, importObject).then(
				obj => {
					console.log(obj);
					obj.instance.exports.init(sampleRate);
					console.log("gen_samples", obj.instance.exports.gen_samples);
					this.gen_samples = obj.instance.exports.gen_samples;
				}
			);
		}
	}


	process(inputList, outputList, parameters) {
		console.log(outputList[0].length);

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


