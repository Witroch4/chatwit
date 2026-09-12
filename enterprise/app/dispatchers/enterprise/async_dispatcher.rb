module Enterprise::AsyncDispatcher
  def listeners
    super + [
      CaptainListener.instance,
      CaptainPaymentReviewListener.instance,
      Captain::ReportingEventListener.instance
    ]
  end
end
