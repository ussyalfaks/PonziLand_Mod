#[macro_export]
macro_rules! get {
    ($entity: expr, $name: literal, $typ: ty) => {{
        use torii_ingester::conversions::FromTy;
        use torii_ingester::error::ToriiConversionError;
        $entity
            .get($name)
            .ok_or_else(|| {
                ToriiConversionError::NestedError(
                    $entity.name.clone(),
                    Box::new(ToriiConversionError::NoSuchField($name.into())),
                )
            })
            .and_then(|val| {
                <$typ>::from_ty(val.clone())
                    .map_err(|e| ToriiConversionError::NestedError($name.into(), Box::new(e)))
            })
            .map(|e| e.into())
    }};
}
