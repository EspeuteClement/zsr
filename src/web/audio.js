class MyAudioProcessor extends AudioWorkletProcessor {
	constructor() {
		super();
	}


	process(inputList, outputList, parameters) {

		for (let output = 0; output < outputList.length; output++) {
			for (let channel = 0; channel < outputList[output].length; channel++) {
				for (let sample = 0; sample < outputList[output][channel].length; sample++) {
					outputList[output][channel][sample] = (Math.random() - 0.5) * 0.75;
				}
			}
		}

		return true;
	}
}

registerProcessor("my-audio-processor", MyAudioProcessor);