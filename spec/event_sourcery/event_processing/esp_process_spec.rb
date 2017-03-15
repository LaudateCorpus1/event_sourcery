RSpec.describe EventSourcery::EventProcessing::ESPProcess do
  subject(:esp_process) do
    described_class.new(
      event_processor: esp,
      event_store: event_store,
      on_event_processor_error: on_event_processor_error,
      stop_on_failure: stop_on_failure,
      subscription_master: subscription_master
    )
  end
  let(:esp) { spy(:esp, processor_name: processor_name) }
  let(:processor_name) { 'processor_name' }
  let(:event_store) { spy(:event_store) }
  let(:stop_on_failure) { false }
  let(:on_event_processor_error) { spy }
  let(:subscription_master) { spy(EventSourcery::EventStore::SubscriptionMaster) }

  describe 'start' do
    subject(:start) { esp_process.start }

    before do
      allow(esp_process).to receive(:sleep).and_return(1)
      allow(Signal).to receive(:trap)
    end

    it 'subscribes the ESP to the event store' do
      start
      expect(esp).to have_received(:subscribe_to)
        .with(event_store,
              subscription_master: subscription_master)
    end

    describe 'graceful shutdown' do
      %i(TERM INT).each do |signal|
        context "upon receiving a #{signal} signal" do
          before do
            allow(Signal).to receive(:trap).with(signal).and_yield
          end

          it 'requests shutdown' do
            start
            expect(subscription_master).to have_received(:request_shutdown)
          end
        end
      end
    end

    context 'given the subscription raises an error' do
      let(:error) { StandardError.new }
      let(:logger) { spy(EventSourcery.logger) }

      before do
        allow(EventSourcery).to receive(:logger).and_return(logger)

        counter = 0
        allow(esp).to receive(:subscribe_to) do
          counter += 1
          raise error if counter < 3
        end
      end

      context 'retry enabled' do
        it 'restarts the subscription after each failure' do
          start
          expect(esp).to have_received(:subscribe_to).thrice
        end

        it 'delays before restarting the subscription' do
          start
          expect(esp_process)
            .to have_received(:sleep)
            .with(1)
            .twice
        end

        it 'calls on_event_processor_error with error and processor name' do
          start
          expect(on_event_processor_error)
            .to have_received(:call)
            .with(error, processor_name)
            .twice
        end

        it 'logs the errors' do
          start
          expect(logger).to have_received(:error).twice
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
      end
    end
  end
end
