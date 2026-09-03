// Package v1 is the smoke example's API group.
//
// It deliberately exercises the parts that would break a naive driver:
//   - a cross-package type (metav1.ObjectMeta / metav1.Condition), so imports
//     must actually resolve;
//   - a stdlib-typed field (metav1.Time wraps time.Time), so the stdlib pkg.json
//     must be fed in — the aspect's Imports map omits stdlib edges;
//   - validation markers, so the marker registry must run;
//   - a nested struct, so the type-checker must follow more than one hop.
//
// +kubebuilder:object:generate=true
// +groupName=smoke.rules-k8s.dev
package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

var (
	// GroupVersion is group version used to register these objects.
	GroupVersion = schema.GroupVersion{Group: "smoke.rules-k8s.dev", Version: "v1"}

	// SchemeBuilder is used to add go types to the GroupVersionKind scheme.
	SchemeBuilder = &scheme{GroupVersion: GroupVersion}
)

// scheme is a stand-in for controller-runtime's SchemeBuilder. The example
// deliberately does not depend on controller-runtime: rules_k8s generates
// schemas from types, and dragging the whole controller runtime in just to
// declare a group would make the example lie about what is required.
type scheme struct{ GroupVersion schema.GroupVersion }

// WidgetSpec defines the desired state of Widget.
type WidgetSpec struct {
	// Host is where the widget lives.
	// +kubebuilder:validation:MinLength=1
	Host string `json:"host"`

	// Replicas is how many of it to run.
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=99
	// +optional
	Replicas int32 `json:"replicas,omitempty"`

	// Mode selects the widget's behavior.
	// +kubebuilder:validation:Enum=Fast;Slow
	// +optional
	Mode string `json:"mode,omitempty"`

	// Engine is a nested struct — the type-checker has to follow it.
	// +optional
	Engine *EngineSpec `json:"engine,omitempty"`

	// Settings is opaque on purpose: controller-gen can only render a
	// RawExtension as x-kubernetes-preserve-unknown-fields. It is here so the
	// post_processors seam has something real to act on.
	// +optional
	Settings *runtime.RawExtension `json:"settings,omitempty"`
}

// EngineSpec is the nested type.
type EngineSpec struct {
	// Image is the engine's container image.
	Image string `json:"image"`

	// Args are passed through verbatim.
	// +optional
	Args []string `json:"args,omitempty"`
}

// WidgetStatus defines the observed state of Widget.
type WidgetStatus struct {
	// Conditions comes from apimachinery — resolving it proves cross-package
	// type resolution works, and it transitively pulls metav1.Time (time.Time),
	// which proves the stdlib is reachable.
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// Widget is the Schema for the widgets API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
type Widget struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   WidgetSpec   `json:"spec,omitempty"`
	Status WidgetStatus `json:"status,omitempty"`
}

// WidgetList contains a list of Widget.
//
// +kubebuilder:object:root=true
type WidgetList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Widget `json:"items"`
}
