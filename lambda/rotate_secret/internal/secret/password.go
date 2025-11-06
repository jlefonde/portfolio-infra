package secret

import (
	"fmt"
	"os"
	"strconv"

	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

func setPasswordLength(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	intValue, err := strconv.ParseInt(envValue, 10, 64)
	if err != nil {
		return fmt.Errorf("failed to parse int64 value '%s': %w", envValue, err)
	}

	input.PasswordLength = &intValue
	return nil
}

func setExcludeCharacters(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	input.ExcludeCharacters = &envValue
	return nil
}

func setExcludeLowercase(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	boolValue, err := strconv.ParseBool(envValue)
	if err != nil {
		return fmt.Errorf("failed to parse boolean value '%s': %w", envValue, err)
	}

	input.ExcludeLowercase = &boolValue
	return nil
}

func setExcludeUppercase(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	boolValue, err := strconv.ParseBool(envValue)
	if err != nil {
		return fmt.Errorf("failed to parse boolean value '%s': %w", envValue, err)
	}

	input.ExcludeUppercase = &boolValue
	return nil
}

func setExcludeNumbers(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	boolValue, err := strconv.ParseBool(envValue)
	if err != nil {
		return fmt.Errorf("failed to parse boolean value '%s': %w", envValue, err)
	}

	input.ExcludeNumbers = &boolValue
	return nil
}

func setExcludePunctuation(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	boolValue, err := strconv.ParseBool(envValue)
	if err != nil {
		return fmt.Errorf("failed to parse boolean value '%s': %w", envValue, err)
	}

	input.ExcludePunctuation = &boolValue
	return nil
}

func setIncludeSpace(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	boolValue, err := strconv.ParseBool(envValue)
	if err != nil {
		return fmt.Errorf("failed to parse boolean value '%s': %w", envValue, err)
	}

	input.IncludeSpace = &boolValue
	return nil
}

func setRequireEachIncludedType(input *secretsmanager.GetRandomPasswordInput, envValue string) error {
	boolValue, err := strconv.ParseBool(envValue)
	if err != nil {
		return fmt.Errorf("failed to parse boolean value '%s': %w", envValue, err)
	}

	input.RequireEachIncludedType = &boolValue
	return nil
}

func NewRandomPasswordInput() (*secretsmanager.GetRandomPasswordInput, error) {
	randomPasswordInput := secretsmanager.GetRandomPasswordInput{}
	secretEnvs := map[string]func(*secretsmanager.GetRandomPasswordInput, string) error{
		"SECRET_PASSWORD_LENGTH":            setPasswordLength,
		"SECRET_EXCLUDE_CHARACTERS":         setExcludeCharacters,
		"SECRET_EXCLUDE_LOWERCASE":          setExcludeLowercase,
		"SECRET_EXCLUDE_UPPERCASE":          setExcludeUppercase,
		"SECRET_EXCLUDE_NUMBERS":            setExcludeNumbers,
		"SECRET_EXCLUDE_PUNCTUATION":        setExcludePunctuation,
		"SECRET_INCLUDE_SPACE":              setIncludeSpace,
		"SECRET_REQUIRE_EACH_INCLUDED_TYPE": setRequireEachIncludedType,
	}

	for key, setFunc := range secretEnvs {
		envValue, found := os.LookupEnv(key)
		if found {
			if err := setFunc(&randomPasswordInput, envValue); err != nil {
				return nil, err
			}
		}
	}

	return &randomPasswordInput, nil
}
