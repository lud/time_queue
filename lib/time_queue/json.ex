if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: TimeQueue do
    def encode(tq, opts) do
      Jason.Encode.map(TimeQueue.dump(tq), opts)
    end
  end
end

if Code.ensure_loaded?(JSON.Encoder) do
  defimpl JSON.Encoder, for: TimeQueue do
    def encode(tq, encoder) do
      encoder.(TimeQueue.dump(tq), encoder)
    end
  end
end
