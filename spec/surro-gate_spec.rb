require 'spec_helper'

describe SurroGate do
  let(:proxy) { subject.new }
  let(:sock_1) { Socket.pair(:UNIX, :DGRAM, 0) }
  let(:sock_2) { Socket.pair(:UNIX, :DGRAM, 0) }

  describe '#new' do
    it 'returns with an instance of Selector' do
      expect(proxy).to be_an_instance_of(SurroGate::Selector)
    end
  end

  it 'proxies between two pushed connections' do
    proxy.push(sock_1.first, sock_2.first)

    2.times do
      sock_1.last.write_nonblock('foo')
      sock_2.last.write_nonblock('bar')

      proxy.select(1)
      proxy.each_ready do |left, right|
        right.write_nonblock(left.read_nonblock(3))
      end

      expect(sock_1.last.read_nonblock(3)).to eq('bar')
      expect(sock_2.last.read_nonblock(3)).to eq('foo')
    end
  end

  context 'threaded' do
    let!(:thread) do
      Thread.new do
        loop do
          proxy.select(500)
          proxy.each_ready do |left, right|
            right.write_nonblock(left.read_nonblock(10))
          end
        end
      end
    end

    before do
      proxy.push(sock_1.first, sock_2.first)
      sleep(2)
    end

    it 'transmits in one direction' do
      sock_1.last.write_nonblock('foo')
      sleep(2)
      expect(sock_2.last.read_nonblock(3)).to eq('foo')
    end

    it 'transmits in both directions' do
      sock_1.last.write_nonblock('foo')
      sock_2.last.write_nonblock('bar')
      sleep(2)
      expect(sock_2.last.read_nonblock(3)).to eq('foo')
      expect(sock_1.last.read_nonblock(3)).to eq('bar')
    end
  end
end
