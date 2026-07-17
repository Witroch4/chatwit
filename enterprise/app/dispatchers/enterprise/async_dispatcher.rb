module Enterprise::AsyncDispatcher
  def listeners
    super + [
      CaptainListener.instance,
      CaptainPaymentReviewListener.instance
    ]
  end
end
