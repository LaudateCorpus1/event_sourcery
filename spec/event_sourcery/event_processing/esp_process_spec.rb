RSpec.describe EventSourcery::EventProcessing::ESPProcess do
  subject(:esp_process) do
    described_class.new(
      event_processor: esp,
      event_store: event_store,
      on_event_processor_error: on_event_processor_error,
      stop_on_failure: stop_on_failure,
      subscription_master: subscription_master,
      retry_strategy: retry_strategy
    )
  end
  let(:esp) { spy(:esp, processor_name: processor_name) }
  let(:processor_name) { 'processor_name' }
  let(:event_store) { spy(:event_store) }
  let(:stop_on_failure) { false }
  let(:on_event_processor_error) { spy }
  let(:subscription_master) { spy(EventSourcery::EventStore::SignalHandlingSubscriptionMaster) }
  let(:retry_strategy) { :constant }

  describe 'start' do
    subject(:start) { esp_process.start }

    before do
      @intervals = []
      allow(esp_process).to receive(:sleep) do |interval|
        @intervals << interval
      end
      allow(Process).to receive(:exit)
      allow(Signal).to receive(:trap)
    end

    it 'subscribes the ESP to the event store' do
      start
      expect(esp).to have_received(:subscribe_to)
        .with(event_store,
              subscription_master: subscription_master)
    end

    context 'given the subscription raises an error' do
      let(:error) { StandardError.new }
      let(:logger) { spy(Logger) }
      let(:event_1) { double(uuid: SecureRandom.uuid) }
      let(:event_2) { double(uuid: SecureRandom.uuid) }

      before do
        allow(EventSourcery).to receive(:logger).and_return(logger)
        allow(logger).to receive(:error).and_yield

        counter = 0
        allow(esp).to receive(:subscribe_to) do
          counter += 1
          begin
            raise error if counter < 4
          rescue => e
            raise EventSourcery::EventProcessingError.new(event_1, e) if counter < 3
            raise EventSourcery::EventProcessingError.new(event_2, e) if counter == 3
          end
        end
      end

      context 'retry enabled' do
        it 'restarts the subscription after each failure' do
          start
          expect(esp).to have_received(:subscribe_to).exactly(4).times
        end

        it 'delays before restarting the subscription' do
          start
          expect(esp_process)
            .to have_received(:sleep)
            .with(1)
            .thrice
        end

        it 'calls on_event_processor_error with error and processor name' do
          start
          expect(on_event_processor_error)
            .to have_received(:call)
            .with(error, processor_name)
            .thrice
        end

        it 'logs the errors' do
          start
          expect(logger).to have_received(:error).thrice
        end

        context 'and retry strategy is exponential' do
          let(:retry_strategy) { :exponential }

          it 'delays at exponentially increasing interval before restarting the subscription' do
            start
            expect(esp_process).to have_received(:sleep).with(1).twice
            expect(esp_process).to have_received(:sleep).with(2).once
            expect(@intervals).to eq [1,2,1]
          end
        end
      end

      context 'retry disabled' do
        let(:stop_on_failure) { true }

        it 'aborts after the first failure' do
          start
          expect(esp).to have_received(:subscribe_to).once
        end

        it 'calls on_event_processor_error with error and processor name' do
          start
          expect(on_event_processor_error)
            .to have_received(:call)
            .with(error, processor_name)
            .once
        end

        it 'logs the error' do
          start
          expect(logger).to have_received(:error).once
        end

        it 'stops the process' do
          start
          expect(Process).to have_received(:exit).with(false)
        end
      end
    end
  end
end
