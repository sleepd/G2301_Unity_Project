using UnityEngine;
using UnityEngine.InputSystem;

[RequireComponent(typeof(CharacterController))]
public class FPSController : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] private float moveSpeed = 5f;
    [SerializeField] private float gravity = -9.81f;
    [SerializeField] private InputActionReference moveAction;

    [Header("Look")]
    [SerializeField] private Transform cameraTransform;
    [SerializeField] private InputActionReference lookAction;
    [SerializeField] private float lookSensitivity = 120f;
    [SerializeField] private bool lookUseDeltaTime = false;
    [SerializeField] private float pitchMin = -80f;
    [SerializeField] private float pitchMax = 80f;

    private CharacterController characterController;
    private float verticalVelocity;
    private float pitch;
    private float yaw;

    private void Awake()
    {
        characterController = GetComponent<CharacterController>();
        if (cameraTransform == null)
        {
            Camera foundCamera = GetComponentInChildren<Camera>();
            if (foundCamera != null)
            {
                cameraTransform = foundCamera.transform;
            }
        }
        if (cameraTransform == transform)
        {
            cameraTransform = null;
        }
        yaw = transform.eulerAngles.y;
    }

    private void OnEnable()
    {
        if (moveAction != null)
        {
            moveAction.action.Enable();
        }
        if (lookAction != null)
        {
            lookAction.action.Enable();
        }
    }

    private void OnDisable()
    {
        if (moveAction != null)
        {
            moveAction.action.Disable();
        }
        if (lookAction != null)
        {
            lookAction.action.Disable();
        }
    }

    private void Update()
    {
        Vector2 look = lookAction != null ? lookAction.action.ReadValue<Vector2>() : Vector2.zero;
        float lookScale = lookUseDeltaTime ? Time.deltaTime : 1f;
        float yawDelta = look.x * lookSensitivity * lookScale;
        float pitchDelta = look.y * lookSensitivity * lookScale;

        yaw += yawDelta;
        transform.localRotation = Quaternion.Euler(0f, yaw, 0f);
        if (cameraTransform != null)
        {
            pitch = Mathf.Clamp(pitch - pitchDelta, pitchMin, pitchMax);
            cameraTransform.localRotation = Quaternion.Euler(pitch, 0f, 0f);
        }

        Vector2 input = moveAction != null ? moveAction.action.ReadValue<Vector2>() : Vector2.zero;
        Vector3 move = transform.right * input.x + transform.forward * input.y;
        if (characterController.isGrounded && verticalVelocity < 0f)
        {
            verticalVelocity = -2f;
        }

        verticalVelocity += gravity * Time.deltaTime;
        Vector3 velocity = new Vector3(0f, verticalVelocity, 0f);

        characterController.Move((move * moveSpeed + velocity) * Time.deltaTime);
    }
}
